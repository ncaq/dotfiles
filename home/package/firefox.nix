{
  pkgs,
  lib,
  config,
  ...
}:
{
  programs.firefox = {
    enable = true;
    languagePacks = [
      "ja"
      "en-US"
    ];
    policies = {
      # [policy-templates | Policy Templates for Firefox](https://mozilla.github.io/policy-templates/)
      DisplayBookmarksToolbar = "never";
      FirefoxHome = {
        Search = false; # 検索ボックス非表示
        SponsoredTopSites = false; # スポンサー付きサイト非表示
      };
      Homepage = {
        URL = "chrome://browser/content/blanktab.html";
        Locked = false;
        StartPage = "previous-session";
      };
      NewTabPage = {
        Enabled = false;
        Locked = false;
      };
      PDFjs = {
        Enabled = true;
        DefaultZoomValue = "page-fit";
      };
      RequestedLocales = [ "ja" ]; # 言語設定を日本語に
      TranslateEnabled = false; # 翻訳機能を無効化
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
            "@react-devtools" # 設定不要
            "@ublacklist" # ポリシー非対応
            "aws-extend-switch-roles@toshi.tilfin.com" # ポリシー非対応
            "chatgpt-ctrl-enter-sender@chatgpt-extension.io" # 設定不要
            "extension@redux.devtools" # 設定不要
            "goodbye-rfc-2822-date-time@ncaq.net" # 設定不要
            "google-search-title-qualified@ncaq.net" # 設定不要
            "treestyletab@piro.sakura.ne.jp" # ポリシー非対応
            "uBlock0@raymondhill.net" # ポリシー対応
            "weautopagerize@wantora.github.io" # ポリシー非対応
            "{1be309c5-3e4f-4b99-927d-bb500eb4fa88}" # Augmented Steam - ポリシー非対応
            "{2e5ff8c8-32fe-46d0-9fc8-6b8986621f3c}" # Refined GitHub - ポリシー非対応
            "{2e5ff8c8-32fe-46d0-9fc8-6b8986621f3c}" # Search by Image - 設定不要
            "{37aa84f3-dfba-43ee-8da6-875ec5af3072}" # AWS Favicon - 設定不要
            "{7a7a4a92-a2a0-41d1-9fd7-1e92480d612d}" # Stylus - ポリシー非対応
            "{a8332c60-5b6d-41ee-bfc8-e9bb331d34ad}" # Surfingkeys - ポリシー非対応
            "{bd97f89b-17ba-4539-9fec-06852d07f917}" # Checkmarks - 設定不要
            "{d07ccf11-c0cd-4938-a265-2a4d6ad01189}" # Web Archives - 設定不要
          ]
        );
      "3rdparty" = {
        Extensions = {
          "uBlock0@raymondhill.net" = {
            # https://github.com/gorhill/uBlock/blob/93d8e639ce91b633cd585b0e031ec52cd77413bc/platform/common/managed_storage.json
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
            ];
            toOverwrite = {
              filters = [
                "@@||analytics.google.com"
                "@@||googletagmanager.com"
                "@@||mozilla.org"
              ];
              filterLists = [
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
            };
          };
        };
      };
    };
    profiles =
      let
        base-profile = {
          search = {
            # https://github.com/mozilla-firefox/firefox/blob/09ba48590299a48636b0b4692f43f8fd5c59972b/toolkit/components/search/SearchEngine.sys.mjs#L934
            force = true;
            engines = {
              google.metadata.alias = "g";
              wikipedia-ja.metadata.alias = "w";
              amazon-jp.metadata.alias = "a";
              twitter = {
                name = "Twitter";
                urls = [
                  {
                    template = "https://twitter.com/search";
                    params = [
                      {
                        name = "q";
                        value = "{searchTerms}";
                      }
                    ];
                  }
                ];
                icon = "${pkgs.kdePackages.breeze-icons}/share/icons/breeze-dark/actions/22/im-twitter.svg";
                definedAliases = [
                  "t"
                  "@twitter"
                ];
              };
              eowf = {
                name = "英辞郎 on the WEB Pro お試し版";
                urls = [
                  {
                    template = "https://eowf.alc.co.jp/search";
                    params = [
                      {
                        name = "q";
                        value = "{searchTerms}";
                      }
                    ];
                  }
                ];
                # TODO
                # icon =
                definedAliases = [
                  "e"
                  "@eof"
                ];
              };
              stackexchange = {
                name = "Stack Exchange";
                urls = [
                  {
                    template = "https://stackexchange.com/search";
                    params = [
                      {
                        name = "q";
                        value = "{searchTerms}";
                      }
                    ];
                  }
                ];
                # TODO
                # icon =
                definedAliases = [
                  "s"
                  "@stackexchange"
                ];
              };
              niconico-dic = {
                name = "ニコニコ大百科";
                urls = [
                  {
                    template = "https://dic.nicovideo.jp/s/a/t/{searchTerms}/rev_created/desc/1-";
                  }
                ];
                # TODO
                # icon =
                definedAliases = [ "@nicovideo-dic" ];
              };
              mdn = {
                name = "MDN Web Docs";
                urls = [
                  {
                    template = "https://developer.mozilla.org/ja/search";
                    params = [
                      {
                        name = "q";
                        value = "{searchTerms}";
                      }
                    ];
                  }
                ];
                # TODO
                # icon
                definedAliases = [
                  "m"
                  "@mdn"
                ];
              };
              nixos-packages = {
                name = "NixOS Search - Packages";
                urls = [
                  {
                    template = "https://search.nixos.org/packages";
                    params = [
                      {
                        name = "query";
                        value = "{searchTerms}";
                      }
                    ];
                  }
                ];
                icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
                definedAliases = [
                  "n"
                  "@nixpkgs"
                ];
              };
              hackage = {
                name = "Hackage";
                urls = [
                  {
                    template = "https://hackage.haskell.org/packages/search";
                    params = [
                      {
                        name = "terms";
                        value = "{searchTerms}";
                      }
                    ];
                  }
                ];
                icon = "${pkgs.kdePackages.breeze-icons}/share/icons/breeze-dark/mimetypes/64/text-x-haskell.svg";
                definedAliases = [
                  "h"
                  "@hackage"
                ];
              };
              stackage = {
                name = "Stackage";
                urls = [
                  {
                    template = "https://www.stackage.org/lts/hoogle";
                    params = [
                      {
                        name = "q";
                        value = "{searchTerms}";
                      }
                    ];
                  }
                ];
                # TODO
                # icon =
                definedAliases = [
                  "l"
                  "@stackage"
                ];
              };
              crate = {
                name = "crates.io: Rust Package Registry";
                urls = [
                  {
                    template = "https://crates.io/search";
                    params = [
                      {
                        name = "q";
                        value = "{searchTerms}";
                      }
                    ];
                  }
                ];
                icon = "${pkgs.kdePackages.breeze-icons}/share/icons/breeze-dark/mimetypes/64/text-rust.svg";
                definedAliases = [
                  "r"
                  "@crate"
                ];
              };
              npm = {
                name = "npm";
                urls = [
                  {
                    template = "https://www.npmjs.com/search";
                    params = [
                      {
                        name = "q";
                        value = "{searchTerms}";
                      }
                    ];
                  }
                ];
                icon = "${pkgs.kdePackages.breeze-icons}/share/icons/breeze-dark/mimetypes/64/text-javascript.svg";
                definedAliases = [
                  "j"
                  "@npm"
                ];
              };
            };
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
          settings = {
            "accessibility.typeaheadfind.manual" = false; # 手動の先行入力検索無効
            "browser.aboutConfig.showWarning" = false; # about:config警告を表示しない
            "browser.bookmarks.showMobileBookmarks" = false; # モバイルブックマーク非表示
            "browser.search.separatePrivateDefault.urlbarResult.enabled" = false; # プライベート用検索エンジン分離無効
            "browser.search.suggest.enabled.private" = true; # プライベートブラウジングで検索候補有効
            "browser.tabs.closeWindowWithLastTab" = false; # 最後のタブを閉じてもウィンドウを閉じない
            "browser.uidensity" = 1; # UIをコンパクトモードに設定
            "browser.urlbar.keepPanelOpenDuringImeComposition" = true; # IME入力中にパネルを開いたまま
            "browser.urlbar.maxRichResults" = 16; # URLバーの候補表示数
            "devtools.browsertoolbox.scope" = "everything"; # ブラウザツールボックスのスコープ
            "devtools.command-button-measure.enabled" = true; # 測定ツールボタン有効
            "devtools.command-button-rulers.enabled" = true; # ルーラーボタン有効
            "devtools.command-button-screenshot.enabled" = true; # スクリーンショットボタン有効
            "devtools.debugger.map-scopes-enabled" = true; # デバッガーのスコープマッピング有効
            "devtools.debugger.pause-on-caught-exceptions" = false; # キャッチされた例外で一時停止しない
            "devtools.dom.enabled" = true; # DOMインスペクター有効
            "devtools.inspector.show_pseudo_elements" = true; # 疑似要素表示
            "devtools.responsive.touchSimulation.enabled" = true; # タッチシミュレーション有効
            "devtools.theme" = "dark"; # 開発者ツールのテーマをダークに
            "extensions.webextensions.restrictedDomains" = ""; # 拡張機能の制限ドメインを空に
            "permissions.default.desktop-notification" = 2; # デスクトップ通知をデフォルトで拒否
            "signon.generation.enabled" = false; # パスワード生成機能無効
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true; # userChrome.css使用を有効
            "ui.key.menuAccessKeyFocuses" = false; # メニューアクセスキーでのフォーカス移動無効
          };
        };
      in
      {
        default = base-profile // {
          id = 0;
        };
        google-search-title-qualified = base-profile // {
          id = 1;
          name = "google-search-title-qualified";
        };
      };
  };
  # 各種プロファイルの`users.js`はNix管理の読み取り専用ファイルになりますが、
  # アドオン開発のためと考えるとweb-extがエラーを出すので読み取り専用は望ましくありません。
  # 開発のためのほぼ使い捨てのプロファイルであることを考えると`users.js`はそんなに真面目に管理する必要がないので、
  # 雑に読み取り専用になっているのを解除します。
  home.activation.firefoxUserJsWritable = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD unlink ${config.home.homeDirectory}/.mozilla/firefox/google-search-title-qualified/user.js
  '';
}
