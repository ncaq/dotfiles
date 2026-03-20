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
      # ネットワークを有効化するためではなく、
      # ホストのネットワークスタックから隔離してTCP接続を遮断するために有効化している。
      # hostAddress/localAddressを意図的に設定せず、IPアドレスを持たない状態にしている。
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
          # データベースがホスト側で`ja_JP.UTF-8`で初期化されているため、
          # コンテナ内でも同じロケールが必要。
          i18n.defaultLocale = "ja_JP.UTF-8";
          # `privateUsers = "identity"`によりpeer認証でコンテナ内外のUID/GIDが一致する必要があるため、
          # postgresユーザとDB接続クライアントのUID/GIDを明示的に指定します。
          users = {
            users = {
              postgres = {
                inherit (postgresUser) uid;
                group = "postgres";
                isSystemUser = true;
              };
            }
            // lib.listToAttrs (
              map (name: {
                inherit name;
                value = {
                  inherit (config.containerUsers.${name}) uid;
                  group = name;
                  isSystemUser = true;
                };
              }) clientNames
            );
            groups = {
              postgres.gid = postgresUser.gid;
            }
            // lib.listToAttrs (
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
            # sameuser: データベース名とユーザ名が一致する場合のみ接続を許可する。
            # 各クライアントが他のクライアントのデータベースに接続することを防ぐ。
            authentication = lib.mkForce ''
              local sameuser all peer
              local all postgres peer
            '';
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
      users = {
        postgres = {
          inherit (postgresUser) uid;
          group = "postgres";
          isSystemUser = true;
          home = "/var/lib/postgresql";
        };
      }
      # /run/postgresqlが0750 postgres:postgresのため、
      # ソケットにアクセスするクライアントユーザをpostgresグループに追加する。
      // lib.listToAttrs (
        map (name: {
          inherit name;
          value.extraGroups = [ "postgres" ];
        }) clientNames
      );
      groups.postgres.gid = postgresUser.gid;
    };

    systemd.tmpfiles.rules = [
      "d /run/postgresql 0750 postgres postgres -"
      "d /var/lib/postgresql 0750 postgres postgres -"
    ];
  };
}
