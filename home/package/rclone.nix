{
  lib,
  config,
  isWSL,
  ...
}:
lib.mkIf (!isWSL) {
  programs.rclone = {
    enable = true;
    # Google Driveの初期セットアップ時はしばしば動的なブラウザを必要とするため、
    # そこはある程度手動だと割り切っている。
    remotes.drive = {
      config = {
        type = "drive";
      };
      mounts."GoogleDrive" = {
        enable = true;
        mountPoint = "${config.home.homeDirectory}/GoogleDrive";
      };
    };
  };
}
