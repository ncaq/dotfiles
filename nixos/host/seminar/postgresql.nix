{
  pkgs,
  config,
  lib,
  ...
}:
let
  postgresUser = config.containerUsers.postgres;
  clientNames = config.postgresClient;
in
{
  options.postgresClient = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "List of container user names that need PostgreSQL access via peer authentication";
  };

  config = {
    containers.postgresql = {
      autoStart = true;
      ephemeral = true;
      # Unixソケット経由でのみ接続を受け付けるため、
      # ネットワークスタックを隔離してTCP接続を遮断する。
      privateNetwork = true;
      privateUsers = "identity";
      bindMounts = {
        # Unixソケットディレクトリ。
        # ホスト上のhealthcheckや他のコンテナからの接続経路として共有します。
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
          # peer認証で接続元のUIDからユーザー名を解決するため、
          # 全てのDB接続ユーザーをコンテナ内にも登録する必要があります。
          users = {
            users = lib.listToAttrs (
              map (name: {
                inherit name;
                value = {
                  inherit (config.containerUsers.${name}) uid;
                  group = name;
                  isSystemUser = true;
                };
              }) clientNames
            );
            groups = lib.listToAttrs (
              map (name: {
                inherit name;
                value.gid = config.containerUsers.${name}.gid;
              }) clientNames
            );
          };
          services.postgresql = {
            enable = true;
            # PostgreSQLのバージョンによってdataDirなどが変更される。
            # `stateVersion`依存で定まるが、明示的に指定して意図しないアップグレードを防ぐ。
            # JITコンパイラは単純なクエリには使われないためデメリットが薄いため、
            # 有効にしておくメリットの方が大きいと判断して雑に有効化。
            package = pkgs.postgresql_17_jit;
            ensureDatabases = clientNames;
            ensureUsers = map (name: {
              inherit name;
              ensureDBOwnership = true;
            }) clientNames;
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
  };
}
