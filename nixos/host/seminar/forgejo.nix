{ config, pkgs, ... }:
let
  addr = config.containerAddresses.forgejo;
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
    localAddress = addr.container;
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
        # UID/GID must match host for PostgreSQL peer authentication via bindMounted socket.
        users.users.forgejo = {
          uid = 991;
          group = "forgejo";
        };
        users.groups.forgejo.gid = 986;
        services.forgejo = {
          enable = true;
          database = {
            type = "postgres";
          };
          settings = {
            server = {
              HTTP_PORT = 8080;
              DOMAIN = "forgejo.ncaq.net";
              ROOT_URL = "https://forgejo.ncaq.net/";
              SSH_DOMAIN = "forgejo-ssh.ncaq.net";
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
    uid = 991;
  };
  users.groups.forgejo.gid = 986;
  systemd.tmpfiles.rules = [
    "d /var/lib/forgejo 0750 forgejo forgejo -"
  ];
}
