{ ... }:
{
  programs.thunderbird = {
    enable = true;
    profiles.default = {
      isDefault = true;
      settings = {
        "accessibility.typeaheadfind.manual" = false;
        "browser.aboutConfig.showWarning" = false;
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
}
