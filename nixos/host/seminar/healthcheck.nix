{ config, ... }:
let
  user = config.serviceUser.healthcheck;
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
