{ pkgs, ... }:
{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-configtool
      fcitx5-gtk
      fcitx5-mozc-ut
    ];
  };

  xdg.configFile = {
    "fcitx5/profile" = {
      text = ''
        [Groups/0]
        # Group Name
        Name=デフォルト
        # Layout
        Default Layout=us-dvorak
        # Default Input Method
        DefaultIM=keyboard-us-dvorak
        [Groups/0/Items/0]
        # Name
        Name=mozc
        # Layout
        Layout=
        [Groups/0/Items/1]
        # Name
        Name=keyboard-us-dvorak
        # Layout
        Layout=
        [GroupOrder]
        0=デフォルト
      '';
    };

    "fcitx5/config" = {
      text = ''
        [Hotkey]
        # 入力メソッドの切り替え
        TriggerKeys=
        # トリガーキーを押すたびに切り替える
        EnumerateWithTriggerKeys=True
        # 一時的に第1入力メソッドに切り替える
        AltTriggerKeys=
        # 次の入力メソッドに切り替える
        EnumerateForwardKeys=
        # 前の入力メソッドに切り替える
        EnumerateBackwardKeys=
        # 切り替え時は第1入力メソッドをスキップする
        EnumerateSkipFirst=False
        # 次の入力メソッドグループに切り替える
        EnumerateGroupForwardKeys=
        # 前の入力メソッドグループに切り替える
        EnumerateGroupBackwardKeys=
        # 埋め込みプリエディットの切り替え
        TogglePreedit=
        # Time limit in milliseconds for triggering modifier key shortcuts
        ModifierOnlyKeyTimeout=250
        [Hotkey/ActivateKeys]
        0=Hangul_Hanja
        [Hotkey/DeactivateKeys]
        0=Hangul_Romaja
        [Hotkey/PrevPage]
        0=Up
        [Hotkey/NextPage]
        0=Down
        [Hotkey/PrevCandidate]
        0=Shift+Tab
        [Hotkey/NextCandidate]
        0=Tab
        [Behavior]
        # デフォルトで有効にする
        ActiveByDefault=False
        # フォーカス時に状態をリセット
        resetStateWhenFocusIn=No
        # 入力状態を共有する
        ShareInputState=No
        # アプリケーションにプリエディットを表示する
        PreeditEnabledByDefault=True
        # 入力メソッドを切り替える際に入力メソッドの情報を表示する
        ShowInputMethodInformation=True
        # フォーカスを変更する際に入力メソッドの情報を表示する
        showInputMethodInformationWhenFocusIn=False
        # 入力メソッドの情報をコンパクトに表示する
        CompactInputMethodInformation=True
        # 第1入力メソッドの情報を表示する
        ShowFirstInputMethodInformation=True
        # デフォルトのページサイズ
        DefaultPageSize=10
        # XKB オプションより優先する
        OverrideXkbOption=False
        # カスタム XKB オプション
        CustomXkbOption=
        # Force Enabled Addons
        EnabledAddons=
        # Force Disabled Addons
        DisabledAddons=
        # Preload input method to be used by default
        PreloadInputMethod=True
        # パスワード欄に入力メソッドを許可する
        AllowInputMethodForPassword=False
        # パスワード入力時にプリエディットテキストを表示する
        ShowPreeditForPassword=False
        # ユーザーデータを保存する間隔（分）
        AutoSavePeriod=30
      '';
    };

    "fcitx5/conf/classicui.conf" = {
      text = ''
        # 候補ウィンドウを縦にする
        Vertical Candidate List=False
        # マウスホイールを使用して前または次のページに移動する
        WheelForPaging=True
        # フォント
        Font="Sans 10"
        # メニューフォント
        MenuFont="Sans 10"
        # トレイフォント
        TrayFont="Sans Bold 10"
        # トレイラベルのアウトライン色
        TrayOutlineColor=#000000
        # トレイラベルのテキスト色
        TrayTextColor=#ffffff
        # テキストアイコンを優先する
        PreferTextIcon=False
        # アイコンにレイアウト名を表示する
        ShowLayoutNameInIcon=True
        # 入力メソッドの言語を使用してテキストを表示する
        UseInputMethodLanguageToDisplayText=True
        # テーマ
        Theme=default-dark
        # ダークテーマ
        DarkTheme=default-dark
        # システムのライト/ダーク配色に従う
        UseDarkTheme=True
        # テーマとデスクトップでサポートされている場合は、システムのアクセントカラーに従う
        UseAccentColor=True
        # X11 で Per Screen DPI を使用する
        PerScreenDPI=True
        # フォント DPI を Wayland で強制する
        ForceWaylandDPI=0
        # Wayland で分数スケールを有効にする
        EnableFractionalScale=True
      '';
    };

    "fcitx5/conf/clipboard.conf" = {
      text = ''
        # トリガーキー
        TriggerKey=
        # プライマリの貼り付け
        PastePrimaryKey=
        # エントリー数
        Number of entries=0
        # パスワードマネージャーからのパスワードを表示しない
        IgnorePasswordFromPasswordManager=False
        # パスワードを含んでいる、非表示のクリップボードの内容
        ShowPassword=False
        # パスワードをクリアするまでの秒数
        ClearPasswordAfter=30
      '';
    };

    "fcitx5/conf/keyboard.conf" = {
      text = ''
        # ページサイズ
        PageSize=10
        # 絵文字のヒントを有効にする
        EnableEmoji=True
        # 絵文字のクイックフレーズを有効にする
        EnableQuickPhraseEmoji=True
        # キーモディファイアーを選択
        Choose Modifier=Alt
        # デフォルトでヒントを有効にする
        EnableHintByDefault=True
        # ヒントモードの切り替え
        Hint Trigger=
        # ヒントモードに一時的に切り替え
        One Time Hint Trigger=
        # 新規入力時の動作を使用する
        UseNewComposeBehavior=True
        # 長押しで特殊文字を入力する
        EnableLongPress=False
        [PrevCandidate]
        0=Shift+Tab
        [NextCandidate]
        0=Tab
        [LongPressBlocklist]
        0=konsole
        1=org.kde.konsole
      '';
    };

    "fcitx5/conf/mozc.conf" = {
      text = ''
        # Initial Mode
        InitialMode=Hiragana
        # Shared Input State
        InputState="Follow Global Configuration"
        # Vertical candidate list
        Vertical=True
        # Expand Usage (Requires vertical candidate list)
        ExpandMode="On Focus"
        # Fix embedded preedit cursor at the beginning of the preedit
        PreeditCursorPositionAtBeginning=False
        # Hotkey to expand usage
        ExpandKey=
      '';
    };

    "fcitx5/conf/quickphrase.conf" = {
      text = ''
        # トリガーキー
        TriggerKey=
      '';
    };

    "fcitx5/conf/unicode.conf" = {
      text = ''
        # トリガーキー
        TriggerKey=
      '';
    };
  };
}
