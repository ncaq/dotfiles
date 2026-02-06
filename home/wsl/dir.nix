{
  config,
  username,
  ...
}:
let
  windowsUsername = username;
  WindowsUserHome = "/mnt/c/Users/${windowsUsername}";
in
{
  home.file = {
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
