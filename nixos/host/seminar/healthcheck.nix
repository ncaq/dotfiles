_: {
  # ヘルスチェック用システムユーザー
  users = {
    users.healthcheck = {
      isSystemUser = true;
      group = "healthcheck";
    };
    groups.healthcheck = { };
  };
}
