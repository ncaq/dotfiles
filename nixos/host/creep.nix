{ nixos-hardware, ... }:
{
  imports = [
    ../native-linux

    ../laptop/backlight.nix

    nixos-hardware.nixosModules.lenovo-thinkpad-p16s-amd-gen2

    ./creep/boot.nix
    ./creep/disk.nix
    ./creep/hardware-configuration.nix
  ];
}
