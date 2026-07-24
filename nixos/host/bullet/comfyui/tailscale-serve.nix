# bulletの電源が入っている時に他の端末からもComfyUIを使えるように、
# Tailscale Serveでtailnet内に公開する。
# Funnelではないのでインターネットには公開されない。
# 転送先はcomfyui-proxy.socketなので、
# tailnet経由の初回アクセスでもソケットアクティベーションによるオンデマンド起動が機能する。
# 何のサービスか分かりやすいように、
# また将来他のサービスも公開できるように、
# ルートではなく`/comfy-ui`パスにマウントする。
{ config, ... }:
let
  tailscale = config.services.tailscale.package;
  port = config.containers.comfyui.config.services.comfyui.port;
in
{
  systemd.services.tailscale-serve = {
    description = "Configure Tailscale Serve";
    requires = [
      "tailscaled.service"
    ];
    wants = [
      "comfyui-proxy.socket"
      "tailscale-online.service"
    ];
    after = [
      "comfyui-proxy.socket"
      "tailscale-online.service"
      "tailscaled.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${tailscale}/bin/tailscale serve --bg --https=443 --set-path=/comfy-ui http://127.0.0.1:${toString port}";
      ExecStop = "${tailscale}/bin/tailscale serve --https=443 --set-path=/comfy-ui off";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };
}
