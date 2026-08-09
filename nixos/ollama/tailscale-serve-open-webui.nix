# 各ホストのOpen WebUIをホスト名入りのTailscale Serviceとしてtailnet内に公開する。
{ pkgs, config, ... }:
{
  systemd.services.tailscale-serve-open-webui = import ../../lib/tailscale-serve.nix {
    inherit pkgs;
    tailscale = config.services.tailscale.package;
    service = "svc:open-webui-${config.networking.hostName}";
    label = "Open WebUI";
    port = config.containers.ollama.config.services.open-webui.port;
    socket = "open-webui-proxy.socket";
  };
}
