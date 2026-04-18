{ config, pkgs, ... }:
let
  addr = config.machineAddresses.forgejo;
  user = config.serviceUser.forgejo;
  postgresGid = config.serviceUser.postgres.gid;
  forgejoUser = {
    inherit (user) uid;
    group = "forgejo";
    isSystemUser = true;
  };
  # ホストからコンテナ内のforgejoコマンドを実行するラッパースクリプト
  forgejoWrapper = pkgs.writeShellApplication {
    name = "forgejo";
    runtimeInputs = with pkgs; [ nixos-container ];
    text = ''
      exec nixos-container run forgejo -- forgejo "$@"
    '';
  };
in
{
  containers.forgejo = {
    autoStart = true;
    ephemeral = true;
    privateNetwork = true;
    privateUsers = "identity";
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
        networking = {
          useHostResolvConf = lib.mkForce false;
          firewall.allowedTCPPorts = [
            2222 # ssh
            8080 # http
          ];
        };
        users = {
          users.forgejo = forgejoUser // {
            extraGroups = [ "postgres" ];
          };
          groups = {
            forgejo.gid = user.gid;
            postgres.gid = postgresGid;
          };
        };
        services = {
          resolved.enable = true;
          forgejo = {
            enable = true;
            database = {
              type = "postgres";
              # PostgreSQLは直接接続されないため、NixOSによるデータベース自動生成機能は無効にします。
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
        };
        # コンテナ内で管理CLIコマンドを使えるようにします。
        environment.systemPackages = [ config.services.forgejo.package ];
      };
  };

  users = {
    users.forgejo = forgejoUser;
    groups.forgejo.gid = user.gid;
  };

  postgresClient = [ "forgejo" ];

  systemd = {
    services."container@forgejo" = {
      requires = [ "postgresql-ready.service" ];
      after = [ "postgresql-ready.service" ];
    };
    tmpfiles.rules = [
      "d /var/lib/forgejo 0750 forgejo forgejo -"
    ];
  };

  # コンテナ外部から使える管理CLIコマンド。
  environment.systemPackages = [ forgejoWrapper ];
}
