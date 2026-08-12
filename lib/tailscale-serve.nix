/**
  ホスト上のポートをTailscale Serviceとしてtailnet内へ公開するモジュール。

  公開したいモジュールがこのファイルを直接importして、
  `local.tailscaleServe.services.<name>`を設定する。
  生成されるユニット名は`tailscale-serve-<name>`になる。

  ```nix
  {
    imports = [ ../../lib/tailscale-serve.nix ];
    local.tailscaleServe.services.ollama = {
      service = "svc:ollama-bullet";
      label = "Ollama";
      port = 11434;
      socket = "ollama-proxy.socket";
    };
  }
  ```

  HTTPSへのリダイレクタもこのモジュールが同時に定義する。
  利用側にimportを増やさせるとホストを増やした時に忘れて、
  80番にTCP接続はできるのに転送先が居ないという実行時にしか出ない壊れ方をする。
  同じパスのモジュールはモジュールシステムが重複除去するので、
  公開するServiceが何個あってもリダイレクタの定義は1つに保たれる。

  # 登録の直列化

  `tailscale serve --service=`はtailscaledのprefsにある`AdvertiseServices`を、
  読み込んでから書き戻す形で更新する。
  ホストが複数のServiceを公開していると、
  systemdが順序を持たないユニットを同時に起動した際に更新が互いを上書きして、
  advertiseされないServiceが出る。
  実際にbulletで複数のServiceを同時に再起動すると、
  毎回どれかが落ちる状態を再現している。
  落ちたServiceはDNSこそ引けるので、
  接続がタイムアウトするまで気付けない。

  ホスト上の全てのserveユニットで同じロックを取り、
  Serviceの登録と解除を直列に実行する。

  # 転送先

  転送先はsocket activationのproxyを想定している。
  tailnet経由の初回アクセスでもオンデマンド起動が機能する。

  HTTPSに加えて80番のHTTPリスナーも張り、
  HTTPSへリダイレクトを返すだけのCaddyへ転送する。
  Serve自体にリダイレクトを返すターゲットが無いため転送先が要る。
  80番が閉じたままだと`http://`で飛んできた時にTCP接続ごと拒否される。
  80番はTailscale Serviceの定義側でも開ける必要があり、
  infra.ncaq.netの`tailscale/service.tf`と`tailscale/access-policy.tf`に`tcp:80`が要る。

  # ハードニング

  tailscale CLIはtailscaledのLocalAPIにUNIXソケット経由で接続するだけで、
  実際のプロキシ転送はtailscaled側が行うため、
  UNIXソケットのみ許可のハードニングまで絞れる。
  このサンドボックス下でServiceの登録、
  drainによる停止、
  再起動での再advertise、
  公開URLへのHTTPSアクセスが通ることをbullet上で確認済み。
*/
{
  pkgs,
  lib,
  config,
  hardening,
  ...
}:
let
  cfg = config.local.tailscaleServe;
  tailscale = config.services.tailscale.package;
  lockFile = "/run/lock/tailscale-serve.lock";
  serialize = command: "${lib.getExe' pkgs.util-linux "flock"} ${lockFile} ${command}";
in
{
  options.local.tailscaleServe = {
    services = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            service = lib.mkOption {
              type = lib.types.strMatching "^svc:[^[:space:]]+$";
              description = "`svc:`から始まるTailscale Service名。";
              example = "svc:ollama-bullet";
            };

            label = lib.mkOption {
              type = lib.types.str;
              description = "ユニットのdescriptionに出る人間向けの表示名。";
              example = "Ollama";
            };

            port = lib.mkOption {
              type = lib.types.port;
              description = "転送先のホスト側ポート番号。";
            };

            socket = lib.mkOption {
              type = lib.types.str;
              description = "転送先のsocketユニット名。";
              example = "ollama-proxy.socket";
            };
          };
        }
      );
      default = { };
      description = ''
        tailnet内へ公開するTailscale Service。
        属性名がそのまま`tailscale-serve-<name>`というユニット名になる。
      '';
    };

    redirectPort = lib.mkOption {
      type = lib.types.port;
      readOnly = true;
      default = 8880;
      description = ''
        Tailscale ServeのHTTPリスナーが転送する、HTTPSリダイレクタのポート。
        Caddyがloopbackで待ち受けて、Serveの`--http=80`がここへ転送する。
        待ち受ける側と転送する側の両方が同じ番号を必要とするので1箇所に集める。
      '';
    };
  };

  config = lib.mkIf (cfg.services != { }) {
    systemd.services = lib.mapAttrs' (
      name: serveCfg:
      lib.nameValuePair "tailscale-serve-${name}" {
        description = "Tailscale Serve for ${serveCfg.label}";
        requires = [ "tailscaled.service" ];
        wants = [
          serveCfg.socket
          "caddy.service"
          "tailscale-online.service"
        ];
        after = [
          serveCfg.socket
          "caddy.service"
          "tailscale-online.service"
          "tailscaled.service"
        ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = hardening.unixSocket // {
          Type = "oneshot";
          RemainAfterExit = true;
          # Tailscale Serviceは設定をtailscaledへ永続化してコマンド自体は終了する。
          ExecStart = [
            (serialize "${tailscale}/bin/tailscale serve --service=${serveCfg.service} --https=443 http://127.0.0.1:${toString serveCfg.port}")
            (serialize "${tailscale}/bin/tailscale serve --service=${serveCfg.service} --http=80 http://127.0.0.1:${toString cfg.redirectPort}")
          ];
          # endpoint設定は残して、次回起動時にそのまま再advertiseできるようにする。
          ExecStop = serialize "${tailscale}/bin/tailscale serve drain ${serveCfg.service}";
          # ロックファイルを置くためだけに書き込みを許可する。
          ReadWritePaths = [ "/run/lock" ];
        };
      }
    ) cfg.services;

    # Tailscale Serviceの80番へ来たHTTPリクエストをHTTPSへリダイレクトするバックエンド。
    #
    # ブラウザのURL補完やコピーしたリンクからは`http://`で飛ぶことが多いが、
    # ServeにHTTPSのリスナーしか無いとTCP接続自体が拒否されて到達できない。
    # `tailscale serve`のターゲットに指定できるのはファイルやディレクトリやURLなどだけで、
    # リダイレクトを返す手段が無いため、転送先として最小のHTTPサーバを用意する。
    #
    # Tailscale ServeはバックエンドへHostヘッダをそのまま渡すので、
    # Service名ごとにvhostを分けなくても1つのvhostで全Serviceを賄える。
    # 実際にServe経由のリクエストで`Host: comfyui.border-saurolophus.ts.net`が、
    # そのまま届くことをbullet上で確認済み。
    #
    # `nixos/host/seminar/caddy.nix`の`:8081`と同じく、
    # ホスト名なしのアドレスにしてHTTPだけで待ち受ける。
    # ホスト名を書くとCaddyが自動HTTPSを有効にしてしまう。
    services.caddy = {
      enable = true;
      virtualHosts.":${toString cfg.redirectPort}".extraConfig = ''
        bind 127.0.0.1
        # 301ではなく308を返す。
        # 301はリクエストメソッドの保存が保証されず、
        # POSTがGETへ書き換えられてしまう。
        redir https://{host}{uri} 308
      '';
    };
  };
}
