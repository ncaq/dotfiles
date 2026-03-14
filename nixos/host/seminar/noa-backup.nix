{ pkgs, username, ... }:
{
  # gocryptfsで暗号化されたバックアップディレクトリを、
  # `sudo mount /mnt/noa/backup`で対話的にパスフレーズ入力してマウントできるようにする。
  fileSystems."/mnt/noa/backup" = {
    device = "/mnt/noa/backup.encrypted";
    fsType = "fuse.gocryptfs";
    options = [
      "noauto" # 起動時に自動マウントしない。
      "nofail" # 失敗を許容する。
      "allow_other" # 通常ユーザがアクセス出来るようにする。
    ];
  };
  environment.systemPackages = [ pkgs.gocryptfs ];
  systemd.tmpfiles.rules = [
    # gocryptfs backup mountpoint
    "d /mnt/noa/backup 0000 ${username} users -"
  ];
}
