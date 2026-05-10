{
  config,
  ...
}:
let
  homeDir = config.home.homeDirectory;
in
{
  xdg = {
    enable = true;
    userDirs = {
      # xdgディレクトリを日本語名称にせずにマジョリティな名称にするように明示的に設定。
      enable = true;
      createDirectories = true;

      desktop = "${homeDir}/Desktop";
      download = "${homeDir}/Downloads";

      # シンボリックリンクで管理するため、自動作成対象から外します。
      pictures = null;
      videos = null;

      # publicShareとtemplatesは何に使うべきなのか未だによくわからないので作らない。
      publicShare = null;
      templates = null;
    };
  };

  home.file = {
    # 共通で`Pictures`はGoogle Driveの`Pictures`フォルダを参照します。
    # Google Driveをどちらで解決するかは別のモジュールに任せます。
    "Pictures".source = config.lib.file.mkOutOfStoreSymlink "${homeDir}/GoogleDrive/Pictures";
  };
}
