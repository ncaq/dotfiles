{ ... }:
{
  programs.thunderbird = {
    enable = true;
    profiles.default = {
      isDefault = true;
      settings = {
        "accessibility.typeaheadfind.manual" = false;
        "browser.aboutConfig.showWarning" = false;
        "browser.policies.applied" = true;
        "browser.search.region" = "JP";
        "browser.shell.didSkipDefaultBrowserCheckOnFirstRun" = true;
        "calendar.timezone.local" = "Asia/Tokyo";
        "calendar.ui.version" = 3;
        "calendar.week.start" = 1; # 月曜始まり
        "mail.shell.checkDefaultClient" = true;
        "mail.showCondensedAddresses" = false; # 完全なアドレス表示
        "mail.startup.enabledMailCheckOnce" = true;
        "mail.uidensity" = 0; # コンパクト表示
        "mailnews.default_news_sort_order" = 1;
        "mailnews.default_sort_order" = 1; # 昇順ソート
        "mailnews.message_display.disable_remote_image" = false; # リモート画像表示
      };
    };
  };

  accounts.email.accounts.main = {
    address = "ncaq@ncaq.net";
    userName = "ncaq.net@gmail.com";
    realName = "ncaq";
    primary = true;

    imap = {
      host = "imap.gmail.com";
      port = 993;
      tls.enable = true;
    };

    smtp = {
      host = "smtp.gmail.com";
      port = 465;
      tls.enable = true;
      tls.useStartTls = false;
    };

    thunderbird = {
      enable = true;
      profiles = [ "default" ];
    };
  };
}
