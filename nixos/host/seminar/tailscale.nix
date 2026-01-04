{ ... }:
{
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server"; # Exit Nodeとして動作
  };
  # Exit Nodeとして動作するために転送を許可。
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };
}
