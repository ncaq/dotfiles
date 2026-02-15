{ config, pkgs, ... }:
let
  addr = config.machineAddresses.forgejo;
  user = config.containerUsers.forgejo;
  # ホストからコンテナ内のforgejoコマンドを実行するラッパースクリプト
  forgejoWrapper = pkgs.writeShellScriptBin "forgejo" ''
    exec nixos-container run forgejo -- forgejo "$@"
  '';
in
{
  environment.systemPackages = [ forgejoWrapper ];
  containers.forgejo = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = addr.host;
    localAddress = addr.guest;
    forwardPorts = [
      {
        containerPort = 2222;
        hostPort = 2222;
        protocol = "tcp";
      }
    ];
    bindMounts = {
      "/run/postgresql" = {
        hostPath = "/run/postgresql";
        isReadOnly = true;
      };
      "/var/lib/forgejo" = {
        hostPath = "/var/lib/forgejo";
        isReadOnly = false;
      };
    };
    config =
      { config, lib, ... }:
      {
        system.stateVersion = "25.05";
        networking.useHostResolvConf = lib.mkForce false;
        services.resolved.enable = true;
        # Allow incoming connections from host via private network.
        networking.firewall.trustedInterfaces = [ "eth0" ];
        # UID/GID must match host for PostgreSQL peer authentication via bindMounted socket.
        users.users.forgejo = {
          inherit (user) uid;
          group = "forgejo";
        };
        users.groups.forgejo.gid = user.gid;
        services.forgejo = {
          enable = true;
          database = {
            type = "postgres";
            # PostgreSQL runs on host, accessed via bindMounted socket.
            createDatabase = false;
            socket = "/run/postgresql";
          };
          settings = {
            server = {
              HTTP_PORT = 8080;
              SSH_PORT = 2222;
              DOMAIN = "forgejo.ncaq.net";
              ROOT_URL = "https://forgejo.ncaq.net/";
              SSH_DOMAIN = "ssh.forgejo.ncaq.net";
              START_SSH_SERVER = true;
            };
            session = {
              COOKIE_SECURE = true;
            };
            service = {
              DISABLE_REGISTRATION = true;
              REQUIRE_SIGNIN_VIEW = true;
            };
            repository = {
              DEFAULT_BRANCH = "master";
            };
          };
        };
        # コンテナ内で管理CLIコマンドを使えるようにします。
        environment.systemPackages = [ config.services.forgejo.package ];
      };
  };

  # Host-side user/group configuration for bindMount permissions.
  # UID/GID must match between host and container for PostgreSQL peer authentication.
  users.users.forgejo = {
    isSystemUser = true;
    group = "forgejo";
    inherit (user) uid;
  };
  users.groups.forgejo.gid = user.gid;
  systemd.tmpfiles.rules = [
    "d /var/lib/forgejo 0750 forgejo forgejo -"
  ];

  # Wait for PostgreSQL to be ready before starting container.
  systemd.services."container@forgejo" = {
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
  };
}
