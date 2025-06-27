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
    # 算定的な手順。
    # インストール後、`rclone config`で存在するremoteにGoogle Cloudのsecret tokenを入力。
    # その後の設定ではGoogle側の仕様変更でエラーになるのでC-cで終了。
    # `rclone config reconnect drive:`で接続し直す。
    # `systemctl --user restart rclone-mount:GoogleDrive@drive.service`でサービスを立ち上げ直す。
    remotes.drive = {
      config = {
        type = "drive";
      };
      mounts."GoogleDrive" = {
        enable = true;
        mountPoint = "${config.home.homeDirectory}/GoogleDrive";
        # mount modeのデフォルトだとオフライン時に全くアクセス出来ないのでキャッシュする。
        options = {
          vfs-cache-mode = "full";
          vfs-cache-max-age = "7d";
          vfs-cache-max-size = "20G";
        };
      };
    };
  };
}
