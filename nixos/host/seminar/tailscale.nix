{ config, pkgs, ... }:
{
  # Exit Nodeとして動作するための追加設定。
  # 基本的なTailscale有効化は nixos/core/tailscale.nix で行っています。
  services.tailscale = {
    openFirewall = true;
    permitCertUid = "caddy";
    useRoutingFeatures = "both";
  };

  # IP転送を有効化。
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Tailscale Serve/Funnelでatticキャッシュを公開インターネットに露出する。
  # GitHub Actionsなど外部CIからNixキャッシュとしてアクセス可能にするため。
  systemd.services.tailscale-serve-attic = {
    description = "Tailscale Serve for attic cache";
    requires = [
      "tailscaled.service"
      "caddy.service"
    ];
    after = [
      "tailscaled.service"
      "caddy.service"
    ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ config.services.tailscale.package ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellApplication {
        name = "tailscale-serve-attic-start";
        runtimeInputs = with pkgs; [
          tailscale
        ];
        text = ''
          tailscale serve --bg --set-path /nix/cache/ http://localhost:8081
          tailscale funnel --bg 443
        '';
      };
      ExecStop = pkgs.writeShellApplication {
        name = "tailscale-serve-attic-stop";
        runtimeInputs = with pkgs; [
          tailscale
        ];
        text = ''
          tailscale funnel off 443
          tailscale serve reset
        '';
      };
    };
  };
}
