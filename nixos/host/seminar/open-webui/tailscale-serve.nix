# Open WebUIをTailscale Serviceとしてtailnet内に公開する。
# Funnelではないのでインターネットには公開されない。
#
# 公開するホストはseminarだけなのでService名にホスト名は入れない。
# 推論先の切り替えはOpen WebUIの内側で行うため、
# 利用者から見えるURLはbulletの電源状態によらず変わらない。
{ pkgs, config, ... }:
{
  systemd.services.tailscale-serve-open-webui = import ../../../../lib/tailscale-serve.nix {
    inherit pkgs;
    tailscale = config.services.tailscale.package;
    service = "svc:open-webui";
    label = "Open WebUI";
    port = config.containers.open-webui.config.services.open-webui.port;
    socket = "open-webui-proxy.socket";
  };
}
