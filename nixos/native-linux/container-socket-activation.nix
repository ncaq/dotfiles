/**
  NixOS Containerの中のサービスを、
  ホスト側のsocketへの初回アクセスで起動するproxyを、
  `containers.<name>.local.socketActivation`の宣言から生成する。

  対象ごとにコンテナ名と表示名とポートと疎通確認パスしか違わないため、
  それぞれに同じ形の定義を書くと片方だけ直した差分が残りやすい。

  ```nix
  containers.ollama.local.socketActivation = {
    label = "Ollama";
    port = 11434;
    healthPath = "/api/tags";
  };
  ```

  宣言したコンテナはブート時には起動しない。
  `<name>-proxy.socket`がホストのloopbackで待ち受けて、
  最初の接続で`<name>-proxy.service`がコンテナを起動して中継する。
  転送先はコンテナ側のIPv6アドレスで、
  ホストとコンテナの間はIPv6で繋ぐ(`lib/machine-address4.nix`)。

  アイドル時の自動停止は誤爆が怖いので設定しない。
  停止したい時は手動で`systemctl stop container@<name>.service`する。
*/
{
  lib,
  pkgs,
  config,
  hardening,
  ...
}:
let
  activated = lib.filterAttrs (_: c: c.local.socketActivation != null) config.containers;
  proxyOf =
    name: container:
    let
      inherit (container.local.socketActivation) label port healthPath;
      # アドレスの無いコンテナへは中継できない。
      # そのまま文字列へ埋め込むと原因の分からないエラーで評価が止まるので、理由を添えて止める。
      localAddress6 =
        if container.localAddress6 == null then
          throw "containers.${name}.local.socketActivation: 中継先になる`localAddress6`がありません。`machineAddresses.${name}`を宣言してください"
        else
          container.localAddress6;
      containerService = "container@${name}.service";
    in
    {
      services."${name}-proxy" = {
        description = "systemd-socket-proxyd for on-demand ${label} activation";
        requires = [ containerService ];
        after = [ containerService ];
        # コンテナのready通知より後にサービスがlistenを開始するため、疎通まで待つ。
        preStart = ''
          until ${lib.getExe pkgs.curl} --fail --silent --output /dev/null "http://[${localAddress6}]:${toString port}${healthPath}"; do
            ${pkgs.coreutils}/bin/sleep 1
          done
        '';
        # 受け取ったソケットとコンテナへのTCP接続を仲介するだけなので、
        # capabilityもファイルシステムへのアクセスも不要でハードニングをそのまま適用できる。
        serviceConfig = hardening.network // {
          # systemd-socket-proxydは`bin/`ではなく`lib/systemd/`に配置されるため、
          # `lib.getExe'`は使えない。
          # PID 1と別ビルドにならないように、稼働中のsystemdと同じパッケージから取る。
          #
          # IPv6アドレスを角括弧で囲まずに書くのは間違いではない。
          # systemd-socket-proxydは最後の`:`より前をそのまま名前解決に渡すので、
          # `[::1]:80`は`[::1]`という名前として引かれて失敗し、`::1:80`なら通る。
          ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd ${localAddress6}:${toString port}";
          DynamicUser = true;
          # 初回のDB migrationや埋め込みモデル取得を許容しつつ、疎通待ちに上限を設ける。
          TimeoutStartSec = "5min";
          # 恒久的に起動できない状態で1秒間隔の再試行を繰り返さないよう、
          # nixpkgsの`ollama-model-loader`と同じ指数バックオフを使う。
          Restart = "on-failure";
          RestartSec = "1s";
          RestartMaxDelaySec = "2h";
          RestartSteps = 10;
        };
      };
      sockets."${name}-proxy" = {
        description = "Socket for on-demand ${label} activation";
        # このリポジトリの中から繋ぐもの(Tailscale Serveや各ラッパ)は`[::1]`を指す。
        # 127.0.0.1でも待ち受けるのは、
        # OllamaやComfyUIを叩く外部のツールの多くが既定の接続先を`127.0.0.1`で持っていて、
        # 設定せずに使うとIPv4のloopbackへ繋ぎに来るため。
        listenStreams = [
          "[::1]:${toString port}"
          "127.0.0.1:${toString port}"
        ];
        wantedBy = [ "sockets.target" ];
      };
    };
in
{
  options.containers = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { config, ... }:
        {
          options.local.socketActivation = lib.mkOption {
            type = lib.types.nullOr (
              lib.types.submodule {
                options = {
                  label = lib.mkOption {
                    type = lib.types.str;
                    description = "ユニットのdescriptionに出る人間向けの表示名。";
                  };
                  port = lib.mkOption {
                    type = lib.types.port;
                    description = "コンテナ側とホスト側で共通のポート番号。";
                  };
                  healthPath = lib.mkOption {
                    type = lib.types.str;
                    description = "疎通確認に叩くHTTPのパス。";
                  };
                };
              }
            );
            default = null;
            description = ''
              ホスト側のsocketへの初回アクセスでコンテナを起動するproxyの定義。
              `null`ならproxyを作らない。
            '';
          };

          # `container-template.nix`の既定値より強く、個々のコンテナの宣言よりは弱くする。
          config.autoStart = lib.mkIf (config.local.socketActivation != null) (lib.mkOverride 900 false);
        }
      )
    );
  };

  config.systemd = lib.mkMerge (lib.mapAttrsToList proxyOf activated);
}
