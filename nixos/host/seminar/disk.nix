{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/disk/by-id/dummy";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/efi";
                mountOptions = [
                  "noatime"
                  "fmask=0077"
                  "dmask=0077"
                ];
              };
            };
            nixos-boot = {
              size = "1G";
              type = "EA00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [
                  "noatime"
                  "fmask=0077"
                  "dmask=0077"
                ];
              };
            };
            nixos-root = {
              size = "100%";
              type = "8300";
              content = {
                type = "btrfs";
                subvolumes = {
                  "@" = {
                    mountpoint = "/";
                    mountOptions = [
                      "noatime"
                      "compress=zstd"
                    ];
                  };
                  "@nix-store" = {
                    mountpoint = "/nix/store";
                    mountOptions = [
                      "noatime"
                      "compress=zstd"
                    ];
                  };
                  "@swap" = {
                    mountpoint = "/swap";
                    mountOptions = [
                      "noatime"
                    ];
                  };
                  "@var-log" = {
                    mountpoint = "/var/log";
                    mountOptions = [
                      "noatime"
                      "compress=zstd"
                    ];
                  };
                  "@snapshots" = {
                    mountpoint = "/.snapshots";
                    mountOptions = [
                      "noatime"
                      "compress=zstd"
                    ];
                  };
                };
              };
            };
          };
        };
      };
    };
  };
  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 4 * 1024;
    }
  ];
}
