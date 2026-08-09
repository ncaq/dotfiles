# ホスト側のsocketへの初回アクセスでOllamaコンテナを起動する。
{ pkgs, config, ... }:
{
  systemd = import ../../lib/ollama-socket-activation.nix {
    inherit pkgs;
    name = "ollama";
    label = "Ollama";
    localAddress = config.containers.ollama.localAddress;
    port = config.containers.ollama.config.services.ollama.port;
    healthPath = "/api/tags";
  };
}
