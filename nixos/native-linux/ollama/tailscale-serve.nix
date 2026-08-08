# 各ホストのOllamaをホスト名入りのTailscale Serviceとしてtailnet内に公開する。
{ config, hardening, ... }:
let
  tailscale = config.services.tailscale.package;
  port = config.containers.ollama.config.services.ollama.port;
  service = "svc:ollama-${config.networking.hostName}";
in
{
  systemd.services.tailscale-serve-ollama = {
    description = "Tailscale Serve for Ollama";
    requires = [ "tailscaled.service" ];
    wants = [
      "ollama-proxy.socket"
      "tailscale-online.service"
    ];
    after = [
      "ollama-proxy.socket"
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
