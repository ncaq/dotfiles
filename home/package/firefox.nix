{ pkgs, lib, ... }:
{
  programs.firefox = {
    enable = true;
    languagePacks = [
      "ja"
      "en-US"
    ];
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
    profiles = {
      default = {
        id = 0;
        search = {
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
          "browser.newtabpage.activity-stream.section.highlights.rows" = 4; # ハイライト表示行数
          "browser.newtabpage.activity-stream.showSearch" = false; # 検索ボックス非表示
          "browser.newtabpage.activity-stream.showSponsoredTopSites" = false; # スポンサー付きサイト非表示
          "browser.newtabpage.activity-stream.topSitesRows" = 4; # トップサイト表示行数
          "browser.newtabpage.enabled" = false; # 新規タブページを無効
          "browser.search.separatePrivateDefault.urlbarResult.enabled" = false; # プライベート用検索エンジン分離無効
          "browser.search.suggest.enabled.private" = true; # プライベートブラウジングで検索候補有効
          "browser.shell.didSkipDefaultBrowserCheckOnFirstRun" = true; # デフォルトブラウザチェックをスキップ
          "browser.startup.homepage" = "chrome://browser/content/blanktab.html"; # ホームページをブランクタブに
          "browser.startup.page" = 3; # 起動時に前回のセッションを復元
          "browser.tabs.closeWindowWithLastTab" = false; # 最後のタブを閉じてもウィンドウを閉じない
          "browser.toolbars.bookmarks.visibility" = "never"; # ブックマークツールバーを非表示
          "browser.translations.automaticallyPopup" = false; # 翻訳機能の自動ポップアップ無効
          "browser.uidensity" = 1; # UIをコンパクトモードに設定
          "browser.urlbar.keepPanelOpenDuringImeComposition" = true; # IME入力中にパネルを開いたまま
          "browser.urlbar.maxRichResults" = 16; # URLバーの候補表示数
          "browser.urlbar.showSearchSuggestionsFirst" = false; # 検索候補を最初に表示しない
          "browser.urlbar.suggest.openpage" = false; # 開いているページを候補に表示しない
          "browser.urlbar.tabToSearch.onboard.interactionsLeft" = 0; # Tab-to-Searchオンボード無効
          "browser.urlbar.tabToSearch.onboard.maxShown" = 0; # Tab-to-Searchオンボード表示回数上限
          "browser.urlbar.timesBeforeHidingSuggestionsHint" = 0; # 候補ヒント非表示までの回数
          "devtools.browsertoolbox.scope" = "everything"; # ブラウザツールボックスのスコープ
          "devtools.command-button-measure.enabled" = true; # 測定ツールボタン有効
          "devtools.command-button-rulers.enabled" = true; # ルーラーボタン有効
          "devtools.command-button-screenshot.enabled" = true; # スクリーンショットボタン有効
          "devtools.debugger.map-scopes-enabled" = true; # デバッガーのスコープマッピング有効
          "devtools.debugger.pause-on-caught-exceptions" = false; # キャッチされた例外で一時停止しない
          "devtools.dom.enabled" = true; # DOMインスペクター有効
          "devtools.everOpened" = true; # 開発者ツール使用済みフラグ
          "devtools.inspector.show_pseudo_elements" = true; # 疑似要素表示
          "devtools.responsive.touchSimulation.enabled" = true; # タッチシミュレーション有効
          "devtools.selfxss.count" = 5; # セルフXSSの警告カウンター
          "devtools.theme" = "dark"; # 開発者ツールのテーマをダークに
          "devtools.toolbox.splitconsole.open" = true; # スプリットコンソールを開く
          "extensions.webextensions.restrictedDomains" = ""; # 拡張機能の制限ドメインを空に
          "general.smoothScroll.mouseWheel.migrationPercent" = 0; # スムーススクロールのマウスホイール移行率
          "intl.accept_languages" = "ja"; # 受け入れ言語を日本語に
          "layout.spellcheckDefault" = 0; # スペルチェック無効
          "pdfjs.defaultZoomValue" = "page-height"; # PDFのデフォルトズームを「ページの高さに合わせる」
          "permissions.default.desktop-notification" = 2; # デスクトップ通知をデフォルトで拒否
          "signon.generation.enabled" = false; # パスワード生成機能無効
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true; # userChrome.css使用を有効
          "ui.key.menuAccessKeyFocuses" = false; # メニューアクセスキーでのフォーカス移動無効
        };
      };
    };
  };
}
