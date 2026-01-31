{
  config,
  pkgs,
  ...
}:
let
  addr = config.containerAddresses.mcp-proxy;
in
{
  containers.mcp-proxy = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = addr.host;
    localAddress = addr.container;
    config =
      { lib, ... }:
      {
        system.stateVersion = "25.05";
        networking.useHostResolvConf = lib.mkForce false;
        services.resolved.enable = true;
        networking.firewall.trustedInterfaces = [ "eth0" ];
        systemd.services.mcp-proxy = {
          description = "MCP Proxy for mcp-nixos";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            Restart = "on-failure";
            DynamicUser = true;
            ExecStart = ''
              ${lib.getExe pkgs.mcp-proxy} \
              --host 0.0.0.0 --port 8080 \
              --named-server nixos ${lib.getExe pkgs.mcp-nixos}
            '';
          };
        };
      };
  };
}
