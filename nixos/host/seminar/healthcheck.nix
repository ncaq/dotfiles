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
  # runuserのPAM設定: healthcheckユーザーの場合はpam_unix.soのsessionをスキップしてログ抑制
  security.pam.services.runuser.rules.session = {
    # healthcheckユーザーの場合は次のunixルールをスキップ
    skip-unix-for-healthcheck = {
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
    # 既存のunixルールはorder=10200で実行される(healthcheck以外のユーザーのみ)
  };
}
