{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  # certspotterのhookが検知したイベントを1行のJSONとして追記するログ。
  eventsLog = "/var/lib/certspotter/events.log";
  # この時間以内のイベントがあればMackerelのチェックをCRITICALにします。
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
  };

  # certspotterは起動時にログリストを取得して、
  # 名前解決に失敗するとすぐ終了します。
  # nixpkgsのモジュールは`network.target`しか待たないので、
  # ブート時に回線が繋がる前に起動して失敗してしまいます。
  # 監視が止まったままだと気づけないので、
  # DNSの一時的な障害に備えて再起動もさせます。
  systemd.services.certspotter = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
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
