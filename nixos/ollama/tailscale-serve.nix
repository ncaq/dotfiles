# 各ホストのOllamaをホスト名入りのTailscale Serviceとしてtailnet内に公開する。
{ pkgs, config, ... }:
{
  systemd.services.tailscale-serve-ollama = import ../../lib/tailscale-serve.nix {
    inherit pkgs;
    tailscale = config.services.tailscale.package;
    service = "svc:ollama-${config.networking.hostName}";
    label = "Ollama";
    port = config.containers.ollama.config.services.ollama.port;
    socket = "ollama-proxy.socket";
  };
}
