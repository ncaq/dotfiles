# bulletの電源が入っている時に他の端末からもComfyUIを使えるように、
# Tailscale Serveでtailnet内に公開する。
# Funnelではないのでインターネットには公開されない。
# LoRA Managerは`/loras_static`などのルート絶対URLを使うため、
# 専用のTailscale Service `svc:comfyui`のルートへ公開する。
{ config, ... }:
{
  imports = [ ../../../../lib/tailscale-serve.nix ];

  local.tailscaleServe.services.comfyui = {
    service = "svc:comfyui";
    label = "ComfyUI";
    port = config.containers.comfyui.config.services.comfyui.port;
    socket = "comfyui-proxy.socket";
  };
}
