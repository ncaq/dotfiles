# 各ホストのOpen WebUIをホスト名入りのTailscale Serviceとしてtailnet内に公開する。
{ config, hardening, ... }:
let
  tailscale = config.services.tailscale.package;
  port = config.containers.ollama.config.services.open-webui.port;
  service = "svc:open-webui-${config.networking.hostName}";
in
{
  systemd.services.tailscale-serve-open-webui = {
    description = "Tailscale Serve for Open WebUI";
    requires = [ "tailscaled.service" ];
    wants = [
      "open-webui-proxy.socket"
      "tailscale-online.service"
    ];
    after = [
      "open-webui-proxy.socket"
      "tailscale-online.service"
      "tailscaled.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = hardening.unixSocket // {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${tailscale}/bin/tailscale serve --service=${service} --https=443 http://127.0.0.1:${toString port}";
      ExecStop = "${tailscale}/bin/tailscale serve drain ${service}";
    };
  };
}
