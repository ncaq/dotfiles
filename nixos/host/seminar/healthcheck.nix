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
    # healthcheckユーザーかチェック(success=2で既存unixルールをスキップ)
    check-healthcheck-user = {
      order = config.security.pam.services.runuser.rules.session.unix.order - 1;
      control = "[success=2 default=1]";
      modulePath = "${pkgs.pam}/lib/security/pam_succeed_if.so";
      args = [
        "quiet"
        "user"
        "="
        "healthcheck"
      ];
    };
    # 既存のunixルールはorder=10200で実行される(healthcheck以外のユーザー)
    # healthcheck以外ならunix-silentをスキップ
    skip-silent-for-others = {
      order = config.security.pam.services.runuser.rules.session.unix.order + 1;
      control = "[success=1 default=ignore]";
      modulePath = "${pkgs.pam}/lib/security/pam_succeed_if.so";
      args = [
        "quiet"
        "user"
        "!="
        "healthcheck"
      ];
    };
    # healthcheckユーザーの場合のみ実行(silentオプション付き)
    unix-silent = {
      order = config.security.pam.services.runuser.rules.session.unix.order + 2;
      control = "optional";
      modulePath = "${pkgs.pam}/lib/security/pam_unix.so";
      settings.silent = true;
    };
  };
}
