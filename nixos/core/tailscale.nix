{ lib, ... }:
{
  services.tailscale = {
    enable = true;
    # ベースとなる設定。
    useRoutingFeatures = lib.mkDefault "client";
  };
}
