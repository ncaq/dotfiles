{ config, ... }:
let
  user = config.containerUsers.healthcheck;
in
{
  # ヘルスチェックに使うシステムユーザー。
  users = {
    users.healthcheck = {
      inherit (user) uid;
      group = "healthcheck";
      isSystemUser = true;
    };
    groups.healthcheck.gid = user.gid;
  };

  postgresClient = [ "healthcheck" ];
}
