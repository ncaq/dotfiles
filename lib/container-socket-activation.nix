/**
  NixOS Container内のサービスを、
  ホスト側socketへの初回アクセスで起動するproxyを生成する関数。

  対象がサービス名とポートと疎通確認パスだけしか違わないため、
  それぞれに同じ形の定義を書くと片方だけ直した差分が残りやすい。

  `systemd`へそのまま代入できる`{ services, sockets }`を返す。
*/
{
  pkgs,
  container,
  name,
  label,
  localAddress,
  port,
  healthPath,
}:
let
  hardening = import ./systemd-hardening.nix;
  containerService = "container@${container}.service";
in
{
  services."${name}-proxy" = {
    description = "systemd-socket-proxyd for on-demand ${label} activation";
    requires = [ containerService ];
    after = [ containerService ];
    # コンテナのready通知より後にサービスがlistenを開始するため、疎通まで待つ。
    preStart = ''
      until ${pkgs.lib.getExe pkgs.curl} --fail --silent --output /dev/null "http://${localAddress}:${toString port}${healthPath}"; do
        ${pkgs.coreutils}/bin/sleep 1
      done
    '';
    serviceConfig = hardening.network // {
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
  sockets."${name}-proxy" = {
    description = "Socket for on-demand ${label} activation";
    listenStreams = [
      "127.0.0.1:${toString port}"
      "[::1]:${toString port}"
    ];
    wantedBy = [ "sockets.target" ];
  };
}
