# ホスト側のsocketへの初回アクセスでOpen WebUIコンテナを起動する。
{
  pkgs,
  config,
  hardening,
  ...
}:
{
  systemd = import ../../../../lib/container-socket-activation.nix {
    inherit pkgs hardening;
    container = "open-webui";
    label = "Open WebUI";
    localAddress = config.containers.open-webui.localAddress;
    port = config.containers.open-webui.config.services.open-webui.port;
    healthPath = "/health";
  };
}
