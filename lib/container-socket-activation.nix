/**
  NixOS Container内のサービスを、
  ホスト側socketへの初回アクセスで起動するproxyを生成する関数。

  対象ごとにコンテナ名とアドレスとポートと疎通確認パスしか違わないため、
  それぞれに同じ形の定義を書くと片方だけ直した差分が残りやすい。

  `systemd`へそのまま代入できる`{ services, sockets }`を返す。

  ```nix
  systemd = import ../../lib/container-socket-activation.nix {
    inherit pkgs hardening;
    container = "ollama";
    label = "Ollama";
    localAddress = config.containers.ollama.localAddress;
    port = config.containers.ollama.config.services.ollama.port;
    healthPath = "/api/tags";
  };
  ```

  # 引数

  - `pkgs`: proxyの実行に使うパッケージの供給元
  - `hardening`: `lib/systemd-hardening.nix`の設定集。
    NixOSモジュールへは`flake.nix`の`specialArgs`経由で配布されるものをそのまま渡す
  - `container`: 対象のコンテナ名。
    `container@<container>.service`への依存と、
    `<container>-proxy`というユニット名の両方に使う
  - `label`: ユニットのdescriptionに出る人間向けの表示名
  - `localAddress`: コンテナ側のIPアドレス
  - `port`: コンテナ側とホスト側で共通のポート番号
  - `healthPath`: 疎通確認に叩くHTTPのパス

  アイドル時の自動停止は誤爆が怖いので設定しない。
  停止したい時は手動で`systemctl stop container@<container>.service`する。
*/
{
  pkgs,
  hardening,
  container,
  label,
  localAddress,
  port,
  healthPath,
}:
let
  containerService = "container@${container}.service";
in
{
  services."${container}-proxy" = {
    description = "systemd-socket-proxyd for on-demand ${label} activation";
    requires = [ containerService ];
    after = [ containerService ];
    # コンテナのready通知より後にサービスがlistenを開始するため、疎通まで待つ。
    preStart = ''
      until ${pkgs.lib.getExe pkgs.curl} --fail --silent --output /dev/null "http://${localAddress}:${toString port}${healthPath}"; do
        ${pkgs.coreutils}/bin/sleep 1
      done
    '';
    # 受け取ったソケットとコンテナへのTCP接続を仲介するだけなので、
    # capabilityもファイルシステムへのアクセスも不要でハードニングをそのまま適用できる。
    serviceConfig = hardening.network // {
      # systemd-socket-proxydは`bin/`ではなく`lib/systemd/`に配置されるため、
      # `lib.getExe'`は使えない。
      ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd ${localAddress}:${toString port}";
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
  sockets."${container}-proxy" = {
    description = "Socket for on-demand ${label} activation";
    listenStreams = [
      "127.0.0.1:${toString port}"
      "[::1]:${toString port}"
    ];
    wantedBy = [ "sockets.target" ];
  };
}
