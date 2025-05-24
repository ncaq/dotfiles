{ pkgs, ... }:
{
  programs.firefox = {
    enable = true;

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
