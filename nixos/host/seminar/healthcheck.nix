{ pkgs, config, ... }:
{
  # ヘルスチェック用システムユーザー
  users = {
    users.healthcheck = {
      isSystemUser = true;
      group = "healthcheck";
    };
    groups.healthcheck = { };
  };
  # runuserのPAM設定: healthcheckユーザーの場合のみセッションログを抑制
  security.pam.services.runuser.rules.session = {
    # healthcheckユーザーかチェック
    check-healthcheck-user = {
      order = config.security.pam.services.runuser.rules.session.unix.order - 1;
      control = "[success=1 default=ignore]";
      modulePath = "${pkgs.pam}/lib/security/pam_succeed_if.so";
      args = [
        "quiet"
        "user"
        "="
        "healthcheck"
      ];
    };
    # healthcheckユーザーの場合はsilentで実行
    unix-silent = {
      inherit (config.security.pam.services.runuser.rules.session.unix) order;
      control = "optional";
      modulePath = "${pkgs.pam}/lib/security/pam_unix.so";
      settings.silent = true;
    };
  };
}
