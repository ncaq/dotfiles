{ pkgs, lib, ... }:
{
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server"; # Exit Nodeとして動作
    # [tailscale: Build failure with portlist tests on NixOS 25.05 - "seek /proc/net/tcp: illegal seek" · Issue #438765 · NixOS/nixpkgs](https://github.com/nixos/nixpkgs/issues/438765)
    package = pkgs.tailscale.overrideAttrs (old: {
      checkFlags = builtins.map (
        flag:
        if lib.hasPrefix "-skip=" flag then
          flag + "|^TestGetList$|^TestIgnoreLocallyBoundPorts$|^TestPoller$"
        else
          flag
      ) old.checkFlags;
    });
  };
  # Exit Nodeとして動作するために転送を許可。
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };
}
