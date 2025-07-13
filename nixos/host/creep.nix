{ nixos-hardware, ... }:
{
  imports = [
    ../native-linux

    nixos-hardware.nixosModules.lenovo-thinkpad-p16s-amd-gen2

    ./creep/disk.nix
    ./creep/hardware-configuration.nix

    ../laptop/backlight.nix
  ];
  boot = {
    loader = {
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot/efi";
      };
      timeout = 1;
      systemd-boot = {
        enable = true;
        consoleMode = "max";
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
