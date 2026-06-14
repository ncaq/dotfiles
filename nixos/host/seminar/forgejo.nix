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
  garageAddr = config.machineAddresses.garage.guest;
  # LFSオブジェクトをgarage(S3互換)に保存するためのバケットとキーをidempotentに作成します。
  # name = "forgejo" なので/run/forgejoにキーが書き出され、forgejoユーザーが所有します。
  garageSetup = import ../../../lib/garage-setup.nix {
    inherit pkgs config;
    name = "forgejo";
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
      # garage-setupが出力したS3キーをマウントします。
      # Forgejo自身がRuntimeDirectoryに使う/run/forgejo配下はセットアップと衝突するため避けます。
      "/run/forgejo-secrets" = {
        hostPath = "/run/forgejo";
        isReadOnly = true;
      };
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
        system.stateVersion = "26.05";
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
            # LFSサーバ機能(`LFS_START_SERVER`)を有効化し、
            # `LFS_JWT_SECRET`も自動生成します。
            # 保存先は下の`settings.lfs`でminio(garage)に切り替えます。
            lfs.enable = true;
            database = {
              type = "postgres";
              # PostgreSQLは直接接続されないため、
              # NixOSによるデータベース自動生成機能は無効にします。
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
              lfs = {
                # LFSオブジェクトのストレージにgarage(S3互換)を使用。
                STORAGE_TYPE = "minio";
                MINIO_ENDPOINT = "${garageAddr}:3900";
                MINIO_BUCKET = "forgejo";
                MINIO_LOCATION = "garage";
                # 内部のIP直アクセスのためSSLは不要。
                MINIO_USE_SSL = false;
                # コンテナ間はIP直アクセスのためpath style。
                MINIO_BUCKET_LOOKUP = "path";
              };
            };
            # S3キーはgarage-setupが起動ごとに生成するため、
            # LoadCredential経由でファイルから読み込みます。
            secrets.lfs = {
              MINIO_ACCESS_KEY_ID = "/run/forgejo-secrets/s3-access-key";
              MINIO_SECRET_ACCESS_KEY = "/run/forgejo-secrets/s3-secret-key";
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
    services = {
      "container@forgejo" = {
        requires = [
          "forgejo-garage-setup.service"
          "postgresql-ready.service"
        ];
        after = [
          "forgejo-garage-setup.service"
          "postgresql-ready.service"
        ];
      };
      "forgejo-garage-setup" = garageSetup;
    };
    tmpfiles.rules = [
      "d /var/lib/forgejo 0750 forgejo forgejo -"
    ];
  };

  # コンテナ外部から使える管理CLIコマンド。
  environment.systemPackages = [ forgejoWrapper ];
}
