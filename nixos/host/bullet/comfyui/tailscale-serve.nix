# bulletの電源が入っている時に他の端末からもComfyUIを使えるように、
# Tailscale Serveでtailnet内に公開する。
# Funnelではないのでインターネットには公開されない。
# LoRA Managerは`/loras_static`などのルート絶対URLを使うため、
# 専用のTailscale Service `svc:comfyui`のルートへ公開する。
{
  pkgs,
  config,
  hardening,
  ...
}:
{
  systemd.services.tailscale-serve-comfyui = import ../../../../lib/tailscale-serve.nix {
    inherit pkgs hardening;
    tailscale = config.services.tailscale.package;
    service = "svc:comfyui";
    label = "ComfyUI";
    port = config.containers.comfyui.config.services.comfyui.port;
    socket = "comfyui-proxy.socket";
    inherit (config.local.tailscaleServe) redirectPort;
  };
}
