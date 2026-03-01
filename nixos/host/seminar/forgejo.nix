{ config, pkgs, ... }:
let
  addr = config.machineAddresses.forgejo;
  user = config.containerUsers.forgejo;
  # ファイルシステムとPostgreSQLの認証で必要なためホストとゲストで設定が共通している必要があります。
  forgejoUser = {
    inherit (user) uid;
    group = "forgejo";
    isSystemUser = true;
  };
  # ホストからコンテナ内のforgejoコマンドを実行するラッパースクリプト
  forgejoWrapper = pkgs.writeShellScriptBin "forgejo" ''
    exec nixos-container run forgejo -- forgejo "$@"
  '';
in
{
  containers.forgejo = {
    autoStart = true;
    ephemeral = true;
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
        networking.firewall.trustedInterfaces = [ "eth0" ];
        users.users.forgejo = forgejoUser;
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

  users.users.forgejo = forgejoUser;
  users.groups.forgejo.gid = user.gid;

  systemd.tmpfiles.rules = [
    "d /var/lib/forgejo 0750 forgejo forgejo -"
  ];

  # コンテナ外部から使える管理CLIコマンド。
  environment.systemPackages = [ forgejoWrapper ];

  # Wait for PostgreSQL to be ready before starting container.
  systemd.services."container@forgejo" = {
    requires = [ "postgresql.service" ];
    after = [ "postgresql.service" ];
  };
}
