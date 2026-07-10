{
  lib,
  username,
  inputs,
  ...
}:
let
  # 以下はDvorak変換とEmacs記法マイグレーション機構。
  # xremapはevdevレベル(XKBがDvorakへ変換するより下の層)で動作するため、
  # xremapに渡すキー名はQWERTY物理配置基準で指定する必要がある。
  # 可読性のため設定はDvorak表記で書き、
  # ここでQWERTY(evdev)表記へ変換する。

  # 文字のリテラル表現と、
  # evdevのキー名の対応。
  literalToName = {
    "[" = "leftbrace";
    "]" = "rightbrace";
    "\\" = "backslash";
    "`" = "grave";
    "'" = "apostrophe";
    "," = "comma";
    "." = "dot";
    "/" = "slash";
    "-" = "minus";
    ";" = "semicolon";
    "=" = "equal";
  };
  nameToLiteral = lib.mapAttrs' (literal: name: lib.nameValuePair name literal) literalToName;

  # USキーボードでDvorakとQwertyで差分が生じる範囲のDvorak側の文字配列。
  dvorakChars = lib.stringToCharacters "[]\\`',.pyfgcrl/=aoeuidhtns-;qjkxbmwvz";
  # USキーボードでDvorakとQwertyで差分が生じる範囲のQwerty側の文字配列。
  qwertyChars = lib.stringToCharacters "-=\\`qwertyuiop[]asdfghjkl;'zxcvbnm,./";

  # Dvorak to Qwerty.
  # 単体のキー名を変換する。
  d2q =
    key:
    let
      literal = nameToLiteral.${key} or key;
      index = lib.lists.findFirstIndex (c: c == literal) null dvorakChars;
    in
    if index == null then
      key
    else
      let
        q = builtins.elemAt qwertyChars index;
      in
      literalToName.${q} or q;

  # "C-w"や"C-Shift-w"のようなキー表現の末尾のキーだけを変換する。
  convertExp =
    exp:
    let
      parts = lib.splitString "-" exp;
    in
    lib.concatStringsSep "-" (lib.init parts ++ [ (d2q (lib.last parts)) ]);

  # remapの値(出力アクション)を再帰的に変換する。
  convertAction =
    action:
    if builtins.isString action then
      convertExp action
    else if builtins.isList action then
      map convertAction action
    else if builtins.isAttrs action then
      if action ? remap then
        action // { remap = convertRemap action.remap; }
      else if action ? with_mark then
        action // { with_mark = convertAction action.with_mark; }
      else
        # set_mark, escape_next_keyなどのキー名を含まないアクション。
        action
    else
      action;

  # remapのトリガーキーと出力アクションを変換する。
  convertRemap =
    remap: lib.mapAttrs' (key: action: lib.nameValuePair (convertExp key) (convertAction action)) remap;

  # Dvorak表記のremapを持つkeymapエントリを構築する。
  keymapEntry =
    {
      name,
      application,
      remap,
    }:
    {
      inherit name;
      application.only = application;
      remap = convertRemap remap;
    };
in
{
  imports = [ inputs.xremap-flake.nixosModules.default ];

  # 共通設定。
  services = {
    xremap = {
      enable = true;
      serviceMode = "user"; # アプリケーションごとに挙動を変えたいのでuserモードを使用。
      userName = username;
      watch = true;
      config = {
        modmap = [
          {
            name = "Global";
            remap = {
              "CapsLock" = "C_L";
            };
          }
        ];
        keymap = [
          (keymapEntry {
            name = "Web textarea like Application";
            application =
              let
                # webのtextareaライクな要素をEmacs風キーバインドへ寄せたいアプリケーション。
                # xremapのX11でのアプリケーション名は、
                # `instance.class`形式の`WM_CLASS`に部分一致する。
                webTextareaApplications = [
                  "Chromium"
                  "LM Studio"
                  "Slack"
                  "claude"
                  "copyq"
                  "discord"
                  "firefox"
                  "jetbrains-idea-ce"
                  "thunderbird"
                ];
              in
              "/${lib.concatStringsSep "|" webTextareaApplications}/";
            remap = {
              "C-g" = [
                "esc"
                { set_mark = false; }
              ];
              "C-y" = [
                "C-v"
                { set_mark = false; }
              ];
              "C-slash" = [
                "C-z"
                { set_mark = false; }
              ];
              "C-backslash" = {
                escape_next_key = true;
              };
              "C-a" = {
                with_mark = "home";
              };
              "C-o" = "C-t";
              "M-o" = "C-Shift-t";
              "M-minus" = "C-Shift-t";
              "C-e" = {
                with_mark = "end";
              };
              "C-u" = [
                "home"
                "Shift-end"
                "C-x"
                { set_mark = false; }
                "delete"
              ];
              "C-d" = [
                "delete"
                { set_mark = false; }
              ];
              "M-d" = [
                "C-delete"
                { set_mark = false; }
              ];
              "C-h" = {
                with_mark = "left";
              };
              "M-h" = {
                with_mark = "C-left";
              };
              "C-s" = {
                with_mark = "right";
              };
              "M-s" = {
                with_mark = "C-right";
              };
              "C-t" = {
                with_mark = "up";
              };
              "C-n" = {
                with_mark = "down";
              };
              "C-q" = "C-w";
              "C-k" = [
                "Shift-end"
                "C-x"
                { set_mark = false; }
              ];
              "C-x" = {
                remap = {
                  # xkeysnailのpass_through_key相当は無いため、
                  # 何も出力しないでプレフィックスを終了する。
                  "C-g" = [ ];
                  "h" = [
                    "C-home"
                    "C-a"
                    { set_mark = true; }
                  ];
                };
              };
              "C-b" = [
                "backspace"
                { set_mark = false; }
              ];
              "M-b" = [
                "C-backspace"
                { set_mark = false; }
              ];
              "C-m" = [
                "enter"
                { set_mark = false; }
              ];
              "C-w" = [
                "C-x"
                { set_mark = false; }
              ];
              "M-w" = [
                "C-c"
                { set_mark = false; }
              ];
              "C-space" = {
                set_mark = true;
              };
              "C-Shift-space" = {
                set_mark = true;
              };
            };
          })
          (keymapEntry {
            name = "`C-,`, `C-.`のショートカットを無効化する";
            application = "/LM Studio|Slack|claude|discord/";
            remap = {
              "C-comma" = "muhenkan";
              "C-dot" = "henkan";
            };
          })
          (keymapEntry {
            name = "改行と投稿を統一する";
            application = "/LM Studio|claude|discord/";
            remap = {
              "C-m" = [
                "Shift-enter"
                { set_mark = false; }
              ];
              "enter" = [
                "enter"
                { set_mark = false; }
              ];
            };
          })
          (keymapEntry {
            name = "改行と投稿を統一する";
            application = "/Slack/";
            remap = {
              "C-m" = [
                "enter"
                { set_mark = false; }
              ];
              "enter" = [
                "C-enter"
                { set_mark = false; }
              ];
            };
          })
          (keymapEntry {
            name = "Slack and Discord";
            application = "/Slack|discord/";
            # チャンネルスイッチのキーバインドを使いやすくします。
            remap = {
              # 下に移動。
              "M-j" = "M-Shift-down";
              # 上に移動。
              "M-k" = "M-Shift-up";
              # 下の未読に移動。
              "M-n" = "M-down";
              # 上の未読に移動。
              "M-t" = "M-up";
            };
          })
          (keymapEntry {
            name = "新規チャットのショートカット";
            application = "/claude/";
            remap = {
              "C-o" = "C-k";
            };
          })
        ];
      };
    };
  };

  # X11向けの設定。
  services.xremap.withX11 = true;
}
