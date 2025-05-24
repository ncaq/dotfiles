{ pkgs, ... }:
{
  programs.firefox = {
    enable = true;

    policies = {
      ExtensionSettings = {
        "uBlock0@raymondhill.net" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
          installation_mode = "force_installed";
        };
      };

      "3rdparty" = {
        Extensions = {
          "uBlock0@raymondhill.net" = {
            adminSettings = {
              # 指定された設定値のみを追加
              userSettings = [
                [
                  "cnameUncloakEnabled"
                  "false"
                ]
                [
                  "hyperlinkAuditingDisabled"
                  "false"
                ]
                [
                  "popupPanelSections"
                  "31"
                ]
                [
                  "prefetchingDisabled"
                  "false"
                ]
                [
                  "suspendUntilListsAreLoaded"
                  "false"
                ]
              ];
              selectedFilterLists = [
                "user-filters"
                "ublock-filters"
                "ublock-badware"
                "ublock-quick-fixes"
                "ublock-unbreak"
                "easylist"
                "adguard-generic"
                "urlhaus-1"
                "curben-phishing"
                "fanboy-cookiemonster"
                "ublock-cookies-easylist"
                "adguard-cookies"
                "ublock-cookies-adguard"
                "easylist-chat"
                "easylist-newsletters"
                "easylist-notifications"
                "easylist-annoyances"
                "adguard-mobile-app-banners"
                "adguard-other-annoyances"
                "adguard-popup-overlays"
                "adguard-widgets"
                "ublock-annoyances"
                "JPN-1"
              ];
              toAdd = {
                trustedSiteDirectives = [
                  "127.0.0.1"
                  "chrome-extension-scheme"
                  "hapitas.jp"
                  "localhost"
                  "moppy.jp"
                  "moz-extension-scheme"
                  "ncaq.net"
                  "nicoad.nicovideo.jp"
                  "rebates.jp"
                  "youtube.com"
                ];
                filters = [
                  "@@||analytics.google.com"
                  "@@||googletagmanager.com"
                  "@@||mozilla.org"
                ];
              };
            };
          };
        };
      };
    };
    profiles = {
      default = {
        id = 0;
        isDefault = true;
        settings = {
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          "extensions.webextensions.ExtensionStorageIDB.enabled" = false;
        };
        extensions = {
          force = true;
          packages = with pkgs.nur.repos.rycee.firefox-addons; [
            augmented-steam
            aws-extend-switch-roles3
            react-devtools
            reduxdevtools
            refined-github
            search-by-image
            stylus
            surfingkeys
            tree-style-tab
            ublacklist
            web-archives

            # 登録されていないらしい。
            # aws-extend-switch-roles@toshi.tilfin.com
            # chatgpt-ctrl-enter-sender@chatgpt-extension.io
            # goodbye-rfc-2822-date-time@ncaq.net
            # google-search-title-qualified@ncaq.net
            # {eceab40b-230a-4560-98ed-185ad010633f} # NixOS Packages Search Engine
          ];
        };
        userChrome = ''
          /* ツリー型タブで十分なため標準の横タブを消去。 */
          #main-window[tabsintitlebar="true"]:not([extradragspace="true"]) #TabsToolbar > .toolbar-items {
            opacity: 0;
            pointer-events: none;
          }
          #main-window:not([tabsintitlebar="true"]) #TabsToolbar {
            visibility: collapse !important;
          }
          /* サイドバーのボーダーは領域を無駄に食うので消去。どのコンテンツでも幅を弄ったりはしない。 */
          #sidebar-splitter {
            display: none !important;
          }
          /* 利用しているのがツリー型タブの場合サイドバーの切り換えを除去。他の場合は残す。 */
          #sidebar-box[sidebarcommand="treestyletab_piro_sakura_ne_jp-sidebar-action"] #sidebar-header {
            visibility: collapse;
          }
        '';
      };
    };
  };
}
