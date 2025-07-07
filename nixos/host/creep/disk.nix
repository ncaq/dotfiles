{ ... }:
{
  # diskoは一つのディスクでのデュアルブートには対応していない。
  # よってプリインストールされているWindowsのパーティションを残す必要があるためdiskoは使えない。
  fileSystems = {
    "/boot/efi" = {
      device = "/dev/disk/by-label/SYSTEM";
      fsType = "vfat";
      options = [
        "noatime"
        "fmask=0077"
        "dmask=0077"
      ];
    };
    "/boot" = {
      device = "/dev/disk/by-label/nixos-boot";
      fsType = "ext4";
      options = [ "noatime" ];
    };
    "/" = {
      device = "/dev/mapper/nixos-root";
      fsType = "btrfs";
      options = [
        "noatime"
        "compress=zstd"
        "subvol=@"
      ];
    };
    "/var/log" = {
      device = "/dev/mapper/nixos-root";
      fsType = "btrfs";
      options = [
        "noatime"
        "compress=zstd"
        "subvol=@var-log"
      ];
    };
    "/.snapshots" = {
      device = "/dev/mapper/nixos-root";
      fsType = "btrfs";
      options = [
        "noatime"
        "compress=zstd"
        "subvol=@snapshots"
      ];
    };
  };
}
