{
  pkgs,
  lib,
  config,
  ...
}:
let
  # 分単位で指定する標準的なチェックの間隔。
  check_interval = 3;
  # 標準的なチェックの連続失敗の上限。
  # どのサービスもリビルドが入ったりして再起動した時に一瞬停止するのは避けられないため、
  # 1回の失敗は許容します。
  # この自宅サーバでダウン時間ゼロを達成する気は基本的にありません。
  # なのでブルーグリーンデプロイメントなどは行いません。
  max_check_attempts = 2;
  # チェックのコマンドはなるべく自前で書かずに、既にあるものを使います。
  # Mackerel公式の`pkgs/go-check-plugins`と、
  # 終了コードの決まりが同じNagios向けのプラグインです。
  #
  # 引数の並びから、標準的な間隔と失敗の上限のチェックを作ります。
  # コマンドは`sh -c`で実行されるので、引数を引用して1つの文字列にします。
  mkCheck = args: {
    command = lib.escapeShellArgs args;
    inherit
      check_interval
      max_check_attempts
      ;
  };
  # systemdのユニットがactiveであることのチェック。
  # `--state`を渡さないと、止まっているユニットも正常として扱われます。
  # `--no-startup-time`を渡さないと、ホストの起動にかかった時間も検査されます。
  # 60秒より長いと警告、120秒より長いと異常になり、ユニットの状態は関係ありません。
  # `systemctl`は`mackerel-agent`のユニットの`PATH`から探されます。
  systemdUnitCheck =
    unit:
    mkCheck [
      (lib.getExe pkgs.nagiosPlugins.check_systemd)
      "--unit"
      unit
      "--state"
      "active"
      "--no-startup-time"
      "--no-performance-data"
    ];
  # HTTPの応答のチェック。
  # `check-http`は既定で3xxまでを正常、4xxを警告、5xxと接続の失敗を異常にします。
  # リダイレクトは辿って、辿った先のステータスで判定します。
  # ここでは4xxも異常にしておき、
  # 変えたいチェックだけ`statuses`で読み替えます。
  httpCheck =
    {
      url,
      statuses ? [ "400-499=critical" ],
      extraArgs ? [ ],
    }:
    mkCheck (
      [
        (lib.getExe' pkgs.go-check-plugins "check-http")
        "--url"
        url
        "--timeout"
        "3"
      ]
      ++ lib.concatMap (status: [
        "--status"
        status
      ]) statuses
      ++ extraArgs
    );
  # GitHub ActionsのランナのVMのチェック。
  # VMの中のランナが全てGitHubに登録されていてonlineであることを、GitHubのAPIで確かめます。
  # 登録されていなくても正常として扱う条件は、コマンドの側(`pkgs/mackerel-check-github-runner`)に書いています。
  # APIは登録トークンを発行するのと同じPATで読みます。
  githubRunnerCheck =
    { name, label }:
    let
      vm = config.local.githubRunnerVms.${name};
    in
    mkCheck (
      [
        (lib.getExe pkgs.mackerel-check-github-runner)
        "--label"
        label
        "--token-file"
        config.sops.secrets."runner-registration-pat".path
        "--repository"
        vm.repository
      ]
      ++ lib.concatMap (runner: [
        "--runner"
        runner
      ]) vm.runnerNames
    );
in
{
  services.mackerel-agent = {
    enable = true;
    runAsRoot = true;
    apiKeyFile = config.sops.templates."mackerel-api-key.conf".path;
    settings = {
      # 上流モジュールの既定は`poweroff`で、
      # エージェントが止まるたびにホストのステータスを`poweroff`に変えます。
      # エージェントは止まった理由を区別しないので、
      # 設定の適用で再起動しただけでも電源断として通知されます。
      # 上流モジュールの型は空を許さないので、
      # 起動時と同じ`working`を送らせてステータスを変えないようにします。
      # 本当に電源が落ちた時は死活監視で気付きます。
      host_status.on_stop = "working";
      # disk I/Oメトリクスを物理ディスク単位だけに絞ってノイズを削減する。
      # この正規表現はデバイス名に部分一致したものを収集対象から除外する。
      # 残したいのは物理ディスク全体(nvme0n1, nvme1n1, sda, sdb, sdc)のI/Oだけ。
      # 除外対象は以下の通り。
      # - loop: 中身が空のループバックデバイス。
      # - zram: 圧縮スワップ。物理ディスクアクセスではない。
      # - bcache: HDDをbcache仮想デバイス越しに見たもの。
      #   複数HDDが同一SSDキャッシュを共有しており、
      #   1本のHDDへのI/Oが sd[a-z] -> bcacheN -> bcacheNp1 -> dm-N と多重計上されて増幅する。
      #   物理実体である sd[a-z] だけ残せば各HDDの真のI/Oが分かる。
      # - nvme[0-9]+n[0-9]+p[0-9]+: nvmeのパーティション。親デバイス全体だけ見れば足りる。
      # - sd[a-z][0-9]+: SCSI/SATAディスクのパーティション(現状は無いが将来用)。
      # なおdm-*はmackerel-agentが標準で除外するため明示不要。
      disks.ignore = "loop|zram|bcache|nvme[0-9]+n[0-9]+p[0-9]+|sd[a-z][0-9]+";
      # ヘルスチェックプラグイン
      plugin.checks = {
        ssh = systemdUnitCheck "sshd.service";
        # 正常にする条件は、コマンドの側(`pkgs/mackerel-check-tailscale`)に書いています。
        tailscale = mkCheck [ (lib.getExe pkgs.mackerel-check-tailscale) ] // {
          # 一時的な瞬断で自動復帰するケースが多いため、
          # 失敗を多めに許容します。
          max_check_attempts = 3;
        };
        cloudflared = systemdUnitCheck "cloudflared-tunnel-seminar.service";
        # `nixos/core/caddy.nix`が`::1`限定で立てているヘルスエンドポイント。
        caddy = httpCheck { url = "http://[::1]:2020/health"; };
        samba = systemdUnitCheck "samba-smbd.service";
        # サーバはコンテナ内で動いていて、ホストとはUnixソケットのディレクトリを共有しています。
        # peer認証で繋ぐので、`healthcheck`ユーザになってから実行します。
        # `check-postgresql`はパスワードが空だと接続文字列が崩れてホストの指定が無視されるので、
        # 使われない値を渡しています。
        # 接続の数が70を超えると警告、90を超えると異常になります。
        # 繋がらない時は異常ではなくUNKNOWNを返します。
        postgresql = mkCheck [
          (lib.getExe' pkgs.util-linux "runuser")
          "-u"
          "healthcheck"
          "--"
          (lib.getExe' pkgs.go-check-plugins "check-postgresql")
          "connection"
          "--host"
          "/run/postgresql"
          "--user"
          "healthcheck"
          "--password"
          "unused"
          "--database"
          "healthcheck"
          "--timeout"
          "3"
        ];
        # S3 APIのルートGETはデータ層の過負荷に巻き込まれて遅延しやすいので、
        # admin APIの軽量なlivenessエンドポイント/healthを使います。
        # /healthは認証不要で、quorumを満たせば200、不足すれば503を返します。
        garage = httpCheck { url = "http://[${config.machineAddresses.garage.guest6}]:3903/health"; };
        forgejo = httpCheck { url = "http://[${config.machineAddresses.forgejo.guest6}]:8080"; };
        niks3-public = httpCheck {
          url = "http://[${config.machineAddresses.niks3-public.guest6}]:5751";
        };
        niks3-private = httpCheck {
          url = "http://[${config.machineAddresses.niks3-private.guest6}]:5751";
        };
        # MCPの`ping`を投げて、結果が返ることを見ます。
        # 前段のCaddyだけでなく、MCPサーバ自身が応答していることを確かめられます。
        # セッション無しで`ping`を受け付けるのは、
        # `mcp-nixos.nix`でステートレスにしているからです。
        # JSON-RPCはエラーも200で返すことがあるので、`result`があることも見ます。
        # `check-http`は二重引用符で始まる値をGoの文字列リテラルとして解釈しようとするので、
        # パターンはキーの先頭の引用符を省いています。
        mcp-nixos = httpCheck {
          url = "http://[${config.machineAddresses.mcp-nixos.guest6}]:8080/mcp";
          extraArgs = [
            "--method"
            "POST"
            "-H"
            "Content-Type: application/json"
            "-H"
            "Accept: application/json, text/event-stream"
            "--body"
            (builtins.toJSON {
              jsonrpc = "2.0";
              id = 1;
              method = "ping";
            })
            "--pattern"
            ''result":''
          ];
        };
        github-runner-dotfiles-x64 = githubRunnerCheck {
          name = "github-runner-dotfiles-x64";
          label = "GitHub Runner x64 dotfiles";
        };
        github-runner-cdn-ncaq-net-x64 = githubRunnerCheck {
          name = "github-runner-cdn-ncaq-net-x64";
          label = "GitHub Runner x64 cdn.ncaq.net";
        };
      };
    };
  };
  # チェックコマンドのストアパスが設定に入るので、
  # nixpkgsを更新するとほぼ毎回このユニットは変更扱いになります。
  # 既定では設定の適用の最初に止めて最後に起動するので、
  # 適用にかかる時間だけメトリクスが欠けます。
  # 適用の後に再起動させて、欠ける時間を再起動の一瞬にします。
  systemd.services.mackerel-agent.stopIfChanged = false;
  sops = {
    # Mackerel APIキー(純粋なキー文字列)をsopsで管理
    secrets."mackerel-api-key" = {
      sopsFile = ../../../secrets/seminar/mackerel.yaml;
      key = "api_key";
      owner = "root";
      group = "root";
      mode = "0400";
    };
    # sops.templatesでTOML形式の設定ファイルを生成
    templates."mackerel-api-key.conf" = {
      content = ''
        apikey = "${config.sops.placeholder."mackerel-api-key"}"
      '';
      mode = "0400";
    };
  };
}
