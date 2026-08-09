# ホスト側のsocketへの初回アクセスでOllamaコンテナを起動する。
{
  lib,
  pkgs,
  config,
  hardening,
  ...
}:
let
  port = config.containers.ollama.config.services.ollama.port;
  localAddress = config.containers.ollama.localAddress;
in
{
  systemd = {
    services = {
      ollama-proxy = {
        description = "systemd-socket-proxyd for on-demand Ollama activation";
        requires = [ "container@ollama.service" ];
        after = [ "container@ollama.service" ];
        serviceConfig = hardening.network // {
          ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd ${localAddress}:${toString port}";
          DynamicUser = true;
        };
      };
      "container@ollama" = {
        # container@のready通知より後にOllamaがlistenを開始するため、APIの疎通まで待つ。
        postStart = ''
          until ${lib.getExe pkgs.curl} --fail --silent --output /dev/null "http://${localAddress}:${toString port}/api/tags"; do
            ${pkgs.coreutils}/bin/sleep 1
          done
        '';
      };
    };
    sockets.ollama-proxy = {
      description = "Socket for on-demand Ollama activation";
      listenStreams = [
        "127.0.0.1:${toString port}"
        "[::1]:${toString port}"
      ];
      wantedBy = [ "sockets.target" ];
    };
  };
}
