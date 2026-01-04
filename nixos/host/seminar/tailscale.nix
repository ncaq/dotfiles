{ ... }:
{
  # Exit Nodeとして動作するための追加設定。
  # 基本的なTailscale有効化は nixos/core/tailscale.nix で行っている。
  services.tailscale.useRoutingFeatures = "both";
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };
}
