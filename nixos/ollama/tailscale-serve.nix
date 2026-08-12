# 各ホストのOllamaをホスト名入りのTailscale Serviceとしてtailnet内に公開する。
{ config, ... }:
{
  imports = [ ../../lib/tailscale-serve.nix ];

  local.tailscaleServe.services.ollama = {
    service = import ../../lib/ollama-tailscale-service.nix config.networking.hostName;
    label = "Ollama";
    port = config.containers.ollama.config.services.ollama.port;
    socket = "ollama-proxy.socket";
  };
}
