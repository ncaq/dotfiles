{ nixos-hardware, ... }:
{
  imports = [
    nixos-hardware.nixosModules.lenovo-thinkpad-p16s-amd-gen2
    ./creep/disk.nix
    ./creep/hardware-configuration.nix
  ];
  boot = {
    loader = {
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot/efi";
      };
      systemd-boot.enable = true;
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
