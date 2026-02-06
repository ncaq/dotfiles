{
  config,
  username,
  ...
}:
let
  windowsUsername = username;
  windowsUserHome = "/mnt/c/Users/${windowsUsername}";
in
{
  home.file = {
    # Windowsホストの管理するGoogle Driveディレクトリを参照。
    "GoogleDrive" = {
      source = config.lib.file.mkOutOfStoreSymlink (windowsUserHome + "/マイドライブ");
    };
    # Windows側のSMBで解決。
    "Videos" = {
      # 以下のようにWindows側でコマンドを使って共有ディレクトリをマウントしてください。
      # ```
      # net use S: \\SEMINAR\chihiro /persistent:yes
      # ```
      source = config.lib.file.mkOutOfStoreSymlink "/mnt/s/Videos";
    };
    # WSLで便利なリンク。
    "WinHome" = {
      source = config.lib.file.mkOutOfStoreSymlink windowsUserHome;
    };
    # WSLで便利なリンク。
    "WinDownloads" = {
      source = config.lib.file.mkOutOfStoreSymlink (windowsUserHome + "/Downloads");
    };
  };
}
