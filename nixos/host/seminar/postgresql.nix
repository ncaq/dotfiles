{
  pkgs,
  config,
  lib,
  ...
}:
let
  # PostgreSQLのバージョンによってdataDirなどが変更される。
  # `stateVersion`依存でデフォルトバージョンは定まりますが、
  # 明示的に指定して意図しないアップグレードを防ぎます。
  # JITコンパイラは単純なクエリには使われないためデメリットが薄いため、
  # 有効にしておくメリットの方が大きいと判断して雑に有効化しておきます。
  postgresql = pkgs.postgresql_17_jit;
  postgresUser = config.serviceUser.postgres;
  clientNames = config.postgresClient;
in
{
  options.postgresClient = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "PostgreSQLへpeer認証で接続するクライアントユーザー名のリスト";
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
                  inherit (config.serviceUser.${name}) uid;
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
                value.gid = config.serviceUser.${name}.gid;
              }) clientNames
            );
          };
          services.postgresql = {
            enable = true;
            package = postgresql;
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

    systemd = {
      # コンテナの起動とPostgreSQLの接続受付開始にはタイムラグがあるため、
      # `pg_isready`で実際に接続可能になるまで待機するサービスを用意する。
      # 依存サービスは`container@postgresql.service`ではなくこのサービスをafterに指定する。
      services.postgresql-ready = {
        requires = [ "container@postgresql.service" ];
        after = [ "container@postgresql.service" ];
        bindTo = [ "container@postgresql.service" ];
        # ソケットファイルが未生成の場合`pg_isready`は`--timeout`に関わらず即座に終了するため、
        # systemdのリスタートでリトライさせます。
        # 1秒間隔で最大30回リトライし、
        # それでも接続できなければ失敗とします。
        startLimitBurst = 30;
        startLimitIntervalSec = 60;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "postgres";
          Group = "postgres";
          ExecStart = "${postgresql}/bin/pg_isready -h /run/postgresql --timeout=5";
          Restart = "on-failure";
          RestartSec = "1s";
        };
      };

      tmpfiles.rules = [
        "d /run/postgresql 0750 postgres postgres -"
        "d /var/lib/postgresql 0750 postgres postgres -"
      ];
    };

    # postgresClientに定義されているクライアントユーザ名がserviceUserに定義されていることを検査。
    assertions =
      let
        serviceUserNames = lib.attrNames config.serviceUser;
        unknownClient = lib.filter (name: !(lib.elem name serviceUserNames)) clientNames;
      in
      [
        {
          assertion = unknownClient == [ ];
          message = "postgresClient contains names not defined in serviceUser: ${lib.concatStringsSep ", " unknownClient}";
        }
      ];
  };
}
