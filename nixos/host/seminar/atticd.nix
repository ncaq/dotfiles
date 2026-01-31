{
  config,
  username,
  pkgs,
  ...
}:
let
  addr = config.containerAddresses.atticd;
  user = config.containerUsers.atticd;
  # ホストからコンテナ内のatticd-atticadmコマンドを実行するラッパースクリプト
  atticadmWrapper = pkgs.writeShellScriptBin "atticd-atticadm" ''
    exec nixos-container run atticd -- atticd-atticadm "$@"
  '';
in
{
  # atticdのJWT署名鍵を管理。
  sops.secrets."atticd-env" = {
    sopsFile = ../../../secrets/seminar/atticd.yaml;
    key = "attic_env";
    owner = "atticd";
    group = "atticd";
    mode = "0640";
  };
  environment.systemPackages = [ atticadmWrapper ];
  containers.atticd = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = addr.host;
    localAddress = addr.container;
    bindMounts = {
      "/run/postgresql" = {
        hostPath = "/run/postgresql";
        isReadOnly = true;
      };
      "/mnt/noa/atticd" = {
        hostPath = "/mnt/noa/atticd";
        isReadOnly = false;
      };
      "/etc/atticd.env" = {
        hostPath = "/run/secrets/atticd-env";
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
        # UID/GID must match host for PostgreSQL peer authentication via bindMounted socket.
        users.users.atticd = {
          inherit (user) uid;
          group = "atticd";
        };
        users.groups.atticd.gid = user.gid;
        services.atticd = {
          enable = true;
          # Managed by sops-nix. To update the secret:
          # ```
          # sops secrets/seminar/atticd.yaml
          # ```
          # To generate a new key:
          # ```
          # openssl genrsa -traditional 4096 | base64 -w0
          # ```
          # Then set attic_env to: ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64="<generated_key>"
          environmentFile = "/etc/atticd.env";
          settings = {
            listen = "[::]:8080";
            allowed-hosts = [ "cache.nix.ncaq.net" ];
            api-endpoint = "https://cache.nix.ncaq.net/";
            database.url = "postgresql:///atticd?host=/run/postgresql";
            storage = {
              type = "local";
              path = "/mnt/noa/atticd";
            };
            garbage-collection = {
              interval = "1 day";
              default-retention-period = "6 months";
            };
          };
        };
      };
  };

  # Host-side user/group configuration for bindMount permissions.
  # UID/GID must match between host and container for PostgreSQL peer authentication.
  users.users.atticd = {
    isSystemUser = true;
    group = "atticd";
    inherit (user) uid;
  };
  users.groups.atticd = {
    inherit (user) gid;
    members = [ username ];
  };
  systemd.tmpfiles.rules = [
    "d /mnt/noa/atticd 0755 atticd atticd -"
  ];

  # Wait for PostgreSQL to be ready before starting container.
  systemd.services."container@atticd" = {
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
  };

  # Token generation examples:
  # ```
  # TOKEN="$(sudo atticd-atticadm make-token --sub 'seminar' --validity '4y' --pull 'private' --push 'private' --create-cache 'private')"
  # ```
  # Read/write token example:
  # ```
  # TOKEN=$(sudo atticd-atticadm make-token --sub 'bullet' --validity '4y' --pull 'private' --push 'private')
  # ```
  # Login with token:
  # ```
  # attic login ncaq https://cache.nix.ncaq.net/ "$TOKEN"
  # ```
}
