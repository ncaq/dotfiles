# 各ホストのOllamaをホスト名入りのTailscale Serviceとしてtailnet内に公開する。
{ config, localLib, ... }:
{
  local.tailscaleServe.services.ollama = {
    service = localLib.ollamaTailscaleService config.networking.hostName;
    label = "Ollama";
    port = config.containers.ollama.config.services.ollama.port;
    socket = "ollama-proxy.socket";
  };
}
