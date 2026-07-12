_: {
  # diskoは一つのディスクでのデュアルブートには対応していない。
  # よってプリインストールされているWindowsのパーティションを残す必要があるためdiskoは使えない。
  fileSystems = {
    "/efi" = {
      device = "/dev/disk/by-label/nixos-esp";
      fsType = "vfat";
      options = [
        "noatime"
        "fmask=0077"
        "dmask=0077"
      ];
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
    "/nix/store" = {
      device = "/dev/mapper/nixos-root";
      fsType = "btrfs";
      options = [
        "noatime"
        "compress=zstd"
        "subvol=@nix-store"
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
