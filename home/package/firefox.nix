{ lib, ... }:
{
  programs.firefox = {
    enable = true;
    policies = {
      ExtensionSettings =
        let
          normalInstall =
            addonId:
            lib.nameValuePair addonId {
              installation_mode = "normal_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/${addonId}";
              private_browsing = true;
            };
        in
        builtins.listToAttrs (
          map normalInstall [
            "@react-devtools"
            "@ublacklist"
            "aws-extend-switch-roles@toshi.tilfin.com"
            "chatgpt-ctrl-enter-sender@chatgpt-extension.io"
            "extension@redux.devtools"
            "goodbye-rfc-2822-date-time@ncaq.net"
            "google-search-title-qualified@ncaq.net"
            "treestyletab@piro.sakura.ne.jp"
            "uBlock0@raymondhill.net"
            "weautopagerize@wantora.github.io"
            "{1be309c5-3e4f-4b99-927d-bb500eb4fa88}" # Augmented Steam
            "{2e5ff8c8-32fe-46d0-9fc8-6b8986621f3c}" # Refined GitHub
            "{2e5ff8c8-32fe-46d0-9fc8-6b8986621f3c}" # Search by Image
            "{37aa84f3-dfba-43ee-8da6-875ec5af3072}" # AWS Favicon
            "{7a7a4a92-a2a0-41d1-9fd7-1e92480d612d}" # Stylus
            "{a8332c60-5b6d-41ee-bfc8-e9bb331d34ad}" # Surfingkeys
            "{bd97f89b-17ba-4539-9fec-06852d07f917}" # Checkmarks
            "{d07ccf11-c0cd-4938-a265-2a4d6ad01189}" # Web Archives
            "{eceab40b-230a-4560-98ed-185ad010633f}" # NixOS Packages Search Engine
          ]
        );
    };
    profiles = {
      default = {
        id = 0;
        isDefault = true;
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
