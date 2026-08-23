# bulletの電源が入っている時に他の端末からもComfyUIを使えるように、
# Tailscale Serveでtailnet内に公開する。
# Funnelではないのでインターネットには公開されない。
# LoRA Managerは`/loras_static`などのルート絶対URLを使うため、
# サブパスではなく専用のTailscale Serviceのルートへ公開する。
{ config, ... }:
{
  imports = [ ../../../../lib/tailscale-serve.nix ];

  local.tailscaleServe.services.comfyui = {
    # 中継して接続するseminarの`open-webui/comfyui-backend.nix`と共有する。
    service = import ../../../../lib/comfyui-tailscale-service.nix;
    label = "ComfyUI";
    port = config.containers.comfyui.config.services.comfyui.port;
    socket = "comfyui-proxy.socket";
  };
}
