_: {
  programs.keepassxc = {
    enable = true;
    settings = {
      # https://github.com/keepassxreboot/keepassxc/blob/develop/src/core/Config.cpp
      General = {
        AutoReloadOnChange = true; # 外部でデータベースが変更された時に自動的に再読み込み
        AutoSaveAfterEveryChange = true; # 変更後に自動保存してパスワード生成後の保存忘れを防ぐ
        AutoSaveOnExit = true; # 終了時に自動保存
        BackupBeforeSave = true; # 保存前にバックアップを作成
        ConfigVersion = 2; # 設定ファイルのバージョン
        OpenPreviousDatabasesOnStartup = true; # 起動時に前回開いていたデータベースを開く
        RememberLastDatabases = true; # 最後に使用したデータベースを記憶
        RememberLastKeyFiles = true; # 最後に使用したキーファイルを記憶
        ShowToolbar = true; # ツールバーを表示
        SingleInstance = true; # 単一インスタンスで実行
        UseGroupIconOnEntryCreation = true; # エントリー作成時にグループアイコンを使用
      };
      GUI = {
        AdvancedSettings = true; # 詳細設定を表示
        ApplicationTheme = "dark"; # アプリケーションテーマをdark、light、classicから選択
        CheckForUpdates = false; # アップデートの自動確認を無効化
        ColorPasswords = true; # パスワードの文字種別に色付け
        EntryListColumnSizes = "400, 350, 1000"; # エントリーリストの列幅
        HidePreviewPanel = false; # プレビューパネルを表示
        HideUsernames = false; # ユーザー名を表示
        Language = "system"; # 表示言語をシステムの言語に設定
        MinimizeOnClose = false; # 閉じるボタンで最小化しない
        MinimizeOnStartup = false; # 起動時に最小化しない
        MinimizeToTray = false; # トレイに最小化しない
        MonospaceNotes = true; # ノートを等幅フォントで表示
        ShowTrayIcon = false; # システムトレイアイコンを表示しない
        ToolButtonStyle = 2; # ツールバーボタンのスタイルで0はアイコンのみ、1はテキストのみ、2はアイコンとテキスト
        TrayIconAppearance = "monochrome-light"; # トレイアイコンの外観
      };
      Security = {
        ClearClipboard = false; # クリップボードを自動的にクリアしない
        IconDownloadFallback = true; # アイコンダウンロードのフォールバックを有効化
        PasswordsRepeatVisible = false; # パスワード確認欄を隠さない
      };
      Browser = {
        Enabled = true; # ブラウザ統合を有効化
      };
    };
  };
}
