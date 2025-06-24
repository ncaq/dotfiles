{ ... }:
{
  imports = [
    <nixos-hardware/lenovo/thinkpad/p16s/amd/gen2>
  ];
  boot.loader = {
    efi = {
      canTouchEfiVariables = true;
    };
    grub = {
      enable = true;
      devices = [ "nodev" ];
      efiSupport = true;
      useOSProber = true;
    };
  };
  # プリインストールされているWindowsのパーティションを残す必要があるためdiskoは使えない。
  fileSystems = {
    "/boot/efi" = {
      device = "/dev/disk/by-label/EFI";
      fsType = "vfat";
      options = [ "noatime" ];
    };
    "/boot" = {
      device = "/dev/disk/by-label/nixos-boot";
      fsType = "ext4";
      options = [ "noatime" ];
    };
    "/" = {
      device = "/dev/disk/by-label/nixos-root";
      fsType = "btrfs";
      options = [
        "noatime"
        "compress=zstd"
        "subvol=@"
      ];
    };
    "/var/log" = {
      device = "/dev/disk/by-label/nixos-root";
      fsType = "btrfs";
      options = [
        "noatime"
        "compress=zstd"
        "subvol=@var-log"
      ];
    };
    "/.snapshots" = {
      device = "/dev/disk/by-label/nixos-root";
      fsType = "btrfs";
      options = [
        "noatime"
        "compress=zstd"
        "subvol=@snapshots"
      ];
    };
  };
}
