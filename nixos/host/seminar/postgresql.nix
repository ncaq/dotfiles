{ pkgs, config, ... }:
let
  addr = config.machineAddresses.postgresql;
  postgresUser = config.containerUsers.postgresql;

  forgejoUser = config.containerUsers.forgejo;
  healthcheckUser = config.containerUsers.healthcheck;
  niks3PrivateUser = config.containerUsers.niks3-private;
  niks3PublicUser = config.containerUsers.niks3-public;
in
{
  containers.postgresql = {
    autoStart = true;
    ephemeral = true;
    privateNetwork = true;
    privateUsers = "identity";
    hostAddress = addr.host;
    localAddress = addr.guest;
    bindMounts = {
      # Unixソケットディレクトリ。
      # ホスト上のhealthcheckや他のコンテナからの接続経路として共有する。
      "/run/postgresql" = {
        hostPath = "/run/postgresql";
        isReadOnly = false;
      };
      # PostgreSQLのデータディレクトリ。
      # 永続化が必要。
      "/var/lib/postgresql" = {
        hostPath = "/var/lib/postgresql";
        isReadOnly = false;
      };
    };
    config =
      { lib, ... }:
      {
        system.stateVersion = "25.05";
        networking = {
          useHostResolvConf = lib.mkForce false;
        };
        # peer認証で接続元のUIDからユーザー名を解決するため、
        # 全てのDB接続ユーザーをコンテナ内にも登録する必要がある。
        users = {
          users = {
            healthcheck = {
              inherit (healthcheckUser) uid;
              group = "healthcheck";
              isSystemUser = true;
            };
            niks3-public = {
              inherit (niks3PublicUser) uid;
              group = "niks3-public";
              isSystemUser = true;
            };
            niks3-private = {
              inherit (niks3PrivateUser) uid;
              group = "niks3-private";
              isSystemUser = true;
            };
            forgejo = {
              inherit (forgejoUser) uid;
              group = "forgejo";
              isSystemUser = true;
            };
          };
          groups = {
            healthcheck.gid = healthcheckUser.gid;
            niks3-public.gid = niks3PublicUser.gid;
            niks3-private.gid = niks3PrivateUser.gid;
            forgejo.gid = forgejoUser.gid;
          };
        };
        services = {
          resolved.enable = true;
          postgresql = {
            enable = true;
            # PostgreSQLのバージョンによってdataDirなどが変更される。
            # `stateVersion`依存で定まるが、明示的に指定して意図しないアップグレードを防ぐ。
            # JITコンパイラは単純なクエリには使われないためデメリットが薄いため、
            # 有効にしておくメリットの方が大きいと判断して雑に有効化。
            package = pkgs.postgresql_17_jit;
            ensureDatabases = [
              "healthcheck"
              "niks3-public"
              "niks3-private"
              "forgejo"
            ];
            ensureUsers = [
              {
                name = "healthcheck";
                ensureDBOwnership = true;
              }
              {
                name = "niks3-public";
                ensureDBOwnership = true;
              }
              {
                name = "niks3-private";
                ensureDBOwnership = true;
              }
              {
                name = "forgejo";
                ensureDBOwnership = true;
              }
            ];
          };
        };
      };
  };

  # ホスト側にもpostgresユーザーを作成。
  # bindMountディレクトリの所有権とtmpfilesルールに必要。
  users = {
    users.postgres = {
      inherit (postgresUser) uid;
      group = "postgres";
      isSystemUser = true;
      home = "/var/lib/postgresql";
    };
    groups.postgres.gid = postgresUser.gid;
  };

  systemd.tmpfiles.rules = [
    "d /run/postgresql 0755 postgres postgres -"
    "d /var/lib/postgresql 0750 postgres postgres -"
  ];
}
