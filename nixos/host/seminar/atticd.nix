{
  config,
  username,
  pkgs,
  ...
}:
let
  addr = config.containerAddresses.atticd;
  # ホストからコンテナ内のatticd-atticadmコマンドを実行するラッパースクリプト
  atticadmWrapper = pkgs.writeShellScriptBin "atticd-atticadm" ''
    exec nixos-container run atticd -- atticd-atticadm "$@"
  '';
in
{
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
        hostPath = "/etc/atticd.env";
        isReadOnly = true;
      };
    };
    config =
      { lib, ... }:
      {
        system.stateVersion = "25.05";
        networking.useHostResolvConf = lib.mkForce false;
        services.resolved.enable = true;
        # UID/GID must match host for PostgreSQL peer authentication via bindMounted socket.
        users.users.atticd = {
          uid = 993;
          group = "atticd";
        };
        users.groups.atticd.gid = 988;
        services.atticd = {
          enable = true;
          # ```
          # echo -n 'ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64="'|sudo tee /etc/atticd.env
          # openssl genrsa -traditional 4096|base64 -w0|sudo tee -a /etc/atticd.env
          # echo '"'|sudo tee -a /etc/atticd.env
          # sudo chown atticd: /etc/atticd.env && sudo chmod 640 /etc/atticd.env
          # sudo systemctl restart atticd
          # ```
          environmentFile = "/etc/atticd.env";
          settings = {
            listen = "[::]:80";
            allowed-hosts = [ "nix-cache.ncaq.net" ];
            api-endpoint = "https://nix-cache.ncaq.net/";
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
    uid = 993;
  };
  users.groups.atticd = {
    gid = 988;
    members = [ username ];
  };
  systemd.tmpfiles.rules = [
    "d /mnt/noa/atticd 0755 atticd atticd -"
  ];

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
  # attic login ncaq https://nix-cache.ncaq.net/ "$TOKEN"
  # ```
}
