{
  lib,
  config,
  isWSL,
  username,
  ...
}:
let
  windowsUsername = username;
  WindowsUserHome = "/mnt/c/Users/${windowsUsername}";
in
{
  xdg = {
    enable = true;
    userDirs = {
      # xdgディレクトリを日本語名称にせずにマジョリティな名称にするように明示的に設定。
      enable = true;
      createDirectories = true;

      desktop = "${config.home.homeDirectory}/Desktop";
      download = "${config.home.homeDirectory}/Downloads";
      pictures = "${config.home.homeDirectory}/Pictures";
      videos = "${config.home.homeDirectory}/Videos";

      # publicShareとtemplatesは何に使うべきなのか未だによくわからないので作らない。
      publicShare = null;
      templates = null;
    };
  };

  home.file = {
    # 共通で`Pictures`はGoogle Driveの`Pictures`フォルダを参照する。
    "Pictures" = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/GoogleDrive/Pictures";
    };
  }
  // lib.optionalAttrs isWSL {
    # WindowsのHDD側を参照。
    "Videos" = {
      source = config.lib.file.mkOutOfStoreSymlink "/mnt/d/Videos/";
    };
    # Windowsホストの管理するGoogle Driveディレクトリを参照。
    "GoogleDrive" = {
      source = config.lib.file.mkOutOfStoreSymlink (WindowsUserHome + "/マイドライブ");
    };
    # WSLで便利なリンク。
    "WinHome" = {
      source = config.lib.file.mkOutOfStoreSymlink WindowsUserHome;
    };
    # WSLで便利なリンク。
    "WinDownloads" = {
      source = config.lib.file.mkOutOfStoreSymlink (WindowsUserHome + "/Downloads");
    };
  };
}
