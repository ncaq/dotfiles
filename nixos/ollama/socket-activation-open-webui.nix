# ホスト側のsocketへの初回アクセスでOpen WebUIを含むOllamaコンテナを起動する。
{
  lib,
  pkgs,
  config,
  hardening,
  ...
}:
let
  openWebui = config.containers.ollama.config.services.open-webui;
  localAddress = config.containers.ollama.localAddress;
in
{
  systemd = {
    services.open-webui-proxy = {
      description = "systemd-socket-proxyd for on-demand Open WebUI activation";
      requires = [ "container@ollama.service" ];
      after = [ "container@ollama.service" ];
      # Ollama APIのready後もOpen WebUIの起動には時間がかかるため、UI側だけ追加で待つ。
      preStart = ''
        until ${lib.getExe pkgs.curl} --fail --silent --output /dev/null "http://${localAddress}:${toString openWebui.port}/health"; do
          ${pkgs.coreutils}/bin/sleep 1
        done
      '';
      serviceConfig = hardening.network // {
        ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd ${localAddress}:${toString openWebui.port}";
        DynamicUser = true;
        # 初回のDB migrationや埋め込みモデル取得を許容する。
        TimeoutStartSec = "5min";
        Restart = "on-failure";
        RestartSec = "1s";
      };
    };
    sockets.open-webui-proxy = {
      description = "Socket for on-demand Open WebUI activation";
      listenStreams = [
        "127.0.0.1:${toString openWebui.port}"
        "[::1]:${toString openWebui.port}"
      ];
      wantedBy = [ "sockets.target" ];
    };
  };
}
