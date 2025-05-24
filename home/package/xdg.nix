{
  config,
  lib,
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
      enable = true;
      createDirectories = true;

      desktop = "${config.home.homeDirectory}/Desktop";
      download = "${config.home.homeDirectory}/Downloads";
      pictures = "${config.home.homeDirectory}/Pictures";
      videos = "${config.home.homeDirectory}/Videos";

      publicShare = null;
      templates = null;
    };
  };

  home.file =
    {
      "Pictures" = {
        source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/GoogleDrive/Pictures";
      };
    }
    // (
      if isWSL then
        {
          "Videos" = {
            source = config.lib.file.mkOutOfStoreSymlink "/mnt/d/Videos/";
          };
          "GoogleDrive" = {
            source = config.lib.file.mkOutOfStoreSymlink (WindowsUserHome + "/マイドライブ");
          };
          "WinHome" = {
            source = config.lib.file.mkOutOfStoreSymlink WindowsUserHome;
          };
          "WinDownloads" = {
            source = config.lib.file.mkOutOfStoreSymlink (WindowsUserHome + "/Downloads");
          };
        }
      else
        { }
    );

  home.activation.createGoogleDrive = lib.hm.dag.entryAfter [ "writeBoundary" ] (
    if isWSL then
      ""
    else
      ''
        if [ ! -d "${config.home.homeDirectory}/GoogleDrive" ]; then
          $DRY_RUN_CMD mkdir -p "${config.home.homeDirectory}/GoogleDrive"
        fi
      ''
  );
}
