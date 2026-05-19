_: {
  services.tailscale = {
    # Exit Nodeとして動作するためにサーバでもクライアントでもある設定にする。
    useRoutingFeatures = "both";
    # Tailscale向けのファイアウォールルールを自動的に開放する。
    openFirewall = true;
  };
}
