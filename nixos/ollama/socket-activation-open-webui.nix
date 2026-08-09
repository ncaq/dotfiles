# ホスト側のsocketへの初回アクセスでOpen WebUIを含むOllamaコンテナを起動する。
{ pkgs, config, ... }:
{
  systemd = import ../../lib/ollama-socket-activation.nix {
    inherit pkgs;
    name = "open-webui";
    label = "Open WebUI";
    localAddress = config.containers.ollama.localAddress;
    port = config.containers.ollama.config.services.open-webui.port;
    healthPath = "/health";
  };
}
