_:
{
  # ヘルスチェック用システムユーザー
  users.users.healthcheck = {
    isSystemUser = true;
    group = "healthcheck";
  };
  users.groups.healthcheck = { };
}
