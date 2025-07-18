{ nixos-hardware, ... }:
{
  imports = [
    ../native-linux

    ../laptop/backlight.nix

    nixos-hardware.nixosModules.lenovo-thinkpad-p16s-amd-gen2

    ./creep/disk.nix
    ./creep/hardware-configuration.nix
  ];
  boot = {
    loader = {
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/efi";
      };
      timeout = 1;
      systemd-boot = {
        enable = true;
        consoleMode = "auto";
        xbootldrMountPoint = "/boot";
      };
    };
    initrd = {
      luks.devices = {
        nixos-root = {
          device = "/dev/disk/by-label/nixos-root-crypt";
          allowDiscards = true;
        };
      };
    };
  };
}
