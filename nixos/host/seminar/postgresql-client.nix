/**
  `postgresql.nix`のPostgreSQLへpeer認証で繋ぐコンテナの定型を、
  `containers.<name>.local.postgres`の宣言から生成する。

  コンテナと同じ名前のユーザが、同じ名前のデータベースへUnixソケットで繋ぐ。
  そのために以下を揃える。

  - `postgresClient`へ登録して、データベースとユーザを用意させる
  - ソケットのある`/run/postgresql`を読み取り専用で渡す
  - `/run/postgresql`は`0750 postgres:postgres`なので、
    コンテナの中のユーザもpostgresグループへ入れる。
    ホスト側のユーザは`postgresql.nix`が入れる
  - DBが接続を受け付けてからコンテナを起動する

  peer認証は、接続してきたプロセスのUIDをPostgreSQLのコンテナの中でユーザ名に解決して照合する。
  UIDをずらす`pick`では解決できないので、
  `privateUsers`は`identity`(UID分離なし、capability分離のみ)にする。
  同じ理由でDynamicUserにもできないので、`local.serviceUser`も有効にしてIDを固定したユーザを作る。
*/
{ lib, config, ... }:
let
  hostConfig = config;
  clients = lib.attrNames (lib.filterAttrs (_: c: c.local.postgres) config.containers);
in
{
  options.containers = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, config, ... }:
        {
          options.local.postgres = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "`postgresql.nix`のPostgreSQLへ、コンテナと同じ名前のユーザでpeer認証で繋ぐか。";
          };

          config = lib.mkIf config.local.postgres {
            privateUsers = "identity";
            local.serviceUser = true;
            bindMounts."/run/postgresql" = {
              hostPath = "/run/postgresql";
              isReadOnly = true;
            };
            config.users = {
              users.${name}.extraGroups = [ "postgres" ];
              groups.postgres.gid = hostConfig.serviceUser.postgres.gid;
            };
          };
        }
      )
    );
  };

  config = {
    postgresClient = clients;

    systemd.services = lib.listToAttrs (
      map (
        name:
        lib.nameValuePair "container@${name}" {
          requires = [ "postgresql-ready.service" ];
          after = [ "postgresql-ready.service" ];
        }
      ) clients
    );
  };
}
