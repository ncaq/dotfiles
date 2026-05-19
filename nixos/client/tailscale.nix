_: {
  services.tailscale = {
    # Exit Nodeとしては動作しないクライアント設定。
    useRoutingFeatures = "client";
  };
}
