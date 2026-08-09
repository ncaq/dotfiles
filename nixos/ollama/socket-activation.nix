# ホスト側のsocketへの初回アクセスでOllamaコンテナを起動する。
{ pkgs, config, ... }:
{
  systemd = import ../../lib/container-socket-activation.nix {
    inherit pkgs;
    container = "ollama";
    name = "ollama";
    label = "Ollama";
    localAddress = config.containers.ollama.localAddress;
    port = config.containers.ollama.config.services.ollama.port;
    healthPath = "/api/tags";
  };
}
