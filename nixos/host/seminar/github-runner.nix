{
  pkgs,
  config,
  ...
}:
let
  githubActionsRunnerPackages = import ../../../lib/github-actions-runner-packages.nix {
    inherit pkgs;
  };
  addr = config.machineAddresses.github-runner-seminar-dotfiles-x64;
in
{
  containers.github-runner-seminar-dotfiles-x64 = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = addr.host;
    localAddress = addr.guest;
    bindMounts = {
      "/etc/github-runner-dotfiles-token" = {
        hostPath = config.sops.secrets."github-runner/dotfiles".path;
        isReadOnly = true;
      };
    };
    config =
      { lib, ... }:
      {
        system.stateVersion = "25.05";
        networking.useHostResolvConf = lib.mkForce false;
        services.resolved.enable = true;
        # Allow incoming connections from host via private network.
        networking.firewall.trustedInterfaces = [ "eth0" ];
        services.github-runners.seminar-dotfiles-x64 = {
          enable = true;
          ephemeral = true;
          replace = true;
          extraPackages = githubActionsRunnerPackages;
          tokenFile = "/etc/github-runner-dotfiles-token";
          url = "https://github.com/ncaq/dotfiles";
        };
      };
  };

  sops.secrets."github-runner/dotfiles" = {
    sopsFile = ../../../secrets/seminar/github-runner/dotfiles.yaml;
    key = "pat";
    owner = "root";
    group = "root";
    mode = "0400";
  };
}
