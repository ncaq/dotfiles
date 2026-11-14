{
  pkgs,
  lib,
  config,
  inputs,
  hardening,
  ...
}:
let
  # certspotterが既定で読むCTログの一覧。ChromeとAppleが認めているログを合わせたもの。
  logListUrl = "https://loglist.certspotter.org/monitor.json";
  # 上の一覧から監視しないログを除いたもの。certspotterはこちらを読みます。
  logListFile = "/var/lib/certspotter-loglist/monitor.json";
  # 監視しないCTログのドメイン。そのドメイン自身とサブドメインのログを除きます。
  #
  # Microsec e-szignoのログは配信が遅すぎて追従できません。
  # seminarからは接続1本あたり約6KB/sしか出ず、ログが伸びる速さの数%しか取れません。
  # certspotterは60秒のタイムアウトと再試行を繰り返すだけで、位置が全く進みませんでした。
  # 上流の一覧が指定する並列度は6ですが、HTTP/1.1で16に上げても追いつきません。
  # certspotterの作者もct-policyのメーリングリストで苦情を出しているサーバ側の問題です。
  #
  # ブラウザは運営者の異なる複数のログのSCTを要求するので、
  # 通用する証明書は他のログにも載り、そちらで検知できます。
  # 配信が改善されたら外してください。
  excludedLogDomains = [ "ct.e-szigno.hu" ];

  # 一覧から`excludedLogDomains`のログを除くjqのプログラム。
  # 運営者によって`logs`(RFC 6962)と`tiled_logs`(static-ct-api)の片方しか無いので、
  # 配列になっているものだけを書き換えます。
  logListFilter = pkgs.writeText "certspotter-loglist-filter.jq" ''
    def host: capture("^https://(?<host>[^/]+)").host;
    def excluded:
      ((.monitoring_url // .url) | host) as $host
      | any($domains[]; . as $domain | $host == $domain or ($host | endswith("." + $domain)));
    (.operators[] | (.logs, .tiled_logs) | arrays) |= map(select(excluded | not))
  '';

  # 上流の一覧を取得して、加工してから置き換えます。
  # 取得や加工に失敗した時と、監視するログが1つも残らない時は、前の一覧を残して失敗します。
  # 同じディレクトリで作ってから`mv`するので、certspotterが書きかけを読むことはありません。
  logListUpdate = pkgs.writeShellApplication {
    name = "certspotter-loglist-update";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
    ];
    text = ''
      target="$STATE_DIRECTORY"/${lib.escapeShellArg (baseNameOf logListFile)}
      temporary=$(mktemp "$target.XXXXXX")
      trap 'rm -f "$temporary"' EXIT
      curl --fail --silent --show-error --max-time 60 "$CERTSPOTTER_LOGLIST_URL" |
        jq --argjson domains ${lib.escapeShellArg (builtins.toJSON excludedLogDomains)} \
          --from-file ${logListFilter} >"$temporary"
      jq --exit-status '[.operators[] | (.logs, .tiled_logs) | arrays[]] | length > 0' \
        "$temporary" >/dev/null
      chmod 0644 "$temporary"
      mv --force "$temporary" "$target"
    '';
  };

  # certspotterのhookが検知したイベントを1行のJSONとして追記するログ。
  eventsLog = "/var/lib/certspotter/events.log";
  # この時間以内のイベントがあればMackerelのチェックをWARNINGかCRITICALにします。
  # 証明書の発見はCRITICALで、追従できないCTログがあるといった監視の不調だけならWARNINGです。
  # アラートが一定期間開いたままになることで見落としを防ぎます。
  alertWindowSeconds = 24 * 60 * 60;

  # hookとチェックの中身は`pkgs/certspotter-mackerel`にあります。
  # hookが書いた行をチェックがそのまま読めることは、そのビルドの中のテストが検査します。
  certspotter-mackerel = pkgs.callPackage ../../../pkgs/certspotter-mackerel {
    inherit (inputs) himari-src;
  };

  # サブコマンドと設定の環境変数を付けて、hookとチェックのそれぞれのコマンドにします。
  # certspotterのhookは引数無しで呼ばれるパスしか受け付けないので、ラッパーで包みます。
  # 環境変数の意味は`pkgs/certspotter-mackerel/src/CertspotterMackerel/Config.hs`に書いてあります。
  commands =
    pkgs.runCommand "certspotter-mackerel-commands" { nativeBuildInputs = [ pkgs.makeWrapper ]; }
      ''
        makeWrapper ${lib.getExe certspotter-mackerel} $out/bin/certspotter-hook \
          --add-flags hook \
          --set CERTSPOTTER_EVENTS_LOG ${lib.escapeShellArg eventsLog}
        makeWrapper ${lib.getExe certspotter-mackerel} $out/bin/check-certspotter \
          --add-flags check \
          --set CERTSPOTTER_EVENTS_LOG ${lib.escapeShellArg eventsLog} \
          --set CERTSPOTTER_ALERT_WINDOW_SECONDS ${toString alertWindowSeconds} \
          --set CERTSPOTTER_SERVICE_UNIT certspotter.service \
          --prefix PATH : ${lib.makeBinPath [ config.systemd.package ]}
      '';
in
{
  # Certificate Transparencyログを監視して、
  # ncaq.net向けに発行された証明書を全て検知します。
  #
  # CAAレコードは真面目なCAの誤発行を防ぐだけで、
  # 秘密鍵が漏洩した中間CAによる発行(2026年10月のeMudhraの事件など)には無力です。
  # そのような発行はドメイン側で防げないので、
  # 代わりにCTログで検知して気づけるようにします。
  #
  # 発行元によるフィルタはしません。
  # ncaq.netの証明書はCloudflare Universal SSLとlegoの更新くらいで数が少なく、
  # 全件を目で見たほうが見落としが無いためです。
  services.certspotter = {
    enable = true;
    # 先頭の`.`でncaq.net自身と全てのサブドメインを対象にします。
    watchlist = [ ".ncaq.net" ];
    hooks = [ (lib.getExe' commands "certspotter-hook") ];
    extraFlags = [
      "-logs"
      logListFile
    ];
  };

  # certspotterにはCTログを個別に除く設定が無く、監視するログは`-logs`の一覧だけで決まります。
  # 上流の一覧をそのまま読ませる代わりに、取得して加工したファイルを読ませます。
  # certspotterは一覧のファイルを30分から90分おきに読み直すので、
  # 置き換えるだけで反映されて、消えたログの監視も止まります。
  systemd.services.certspotter-loglist = {
    description = "Fetch the Certificate Transparency log list for Cert Spotter";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    environment.CERTSPOTTER_LOGLIST_URL = logListUrl;
    serviceConfig = hardening.network // {
      Type = "oneshot";
      ExecStart = lib.getExe logListUpdate;
      User = "certspotter";
      Group = "certspotter";
      StateDirectory = "certspotter-loglist";
      # 回線が繋がる前のブート時やDNSの一時的な障害に備えます。
      Restart = "on-failure";
      RestartSec = "1min";
    };
  };

  # 上流の一覧は新しいCTログが増えたり古いログが消えたりして変わるので、定期的に取り直します。
  # certspotter自身が上流を読み直す間隔と同じくらいにします。
  systemd.timers.certspotter-loglist = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      RandomizedDelaySec = "10min";
    };
  };

  # certspotterは起動時にログリストを取得して、
  # 名前解決に失敗するとすぐ終了します。
  # nixpkgsのモジュールは`network.target`しか待たないので、
  # ブート時に回線が繋がる前に起動して失敗してしまいます。
  # 監視が止まったままだと気づけないので、
  # DNSの一時的な障害に備えて再起動もさせます。
  #
  # 起動の前に一覧を取り直します。
  # 取得に失敗しても前の一覧で監視を続けたいので、`requires`ではなく`wants`にします。
  systemd.services.certspotter = {
    wants = [
      "network-online.target"
      "certspotter-loglist.service"
    ];
    after = [
      "network-online.target"
      "certspotter-loglist.service"
    ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "30s";
    };
  };

  # 検知したイベントは既存のMackerelの通知経路に乗せます。
  # mackerel-agentはrootで動くのでcertspotterのstateディレクトリを直接読めます。
  services.mackerel-agent.settings.plugin.checks.certspotter = {
    command = lib.getExe' commands "check-certspotter";
    check_interval = 3;
    # イベントは一定期間残るので連続失敗の判定を待つ意味がなく、
    # すぐに通知を出します。
    max_check_attempts = 1;
  };
}
