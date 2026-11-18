{ config, ... }:
let
  user = config.serviceUser.healthcheck;
in
{
  # ヘルスチェックに使うシステムユーザ。
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
