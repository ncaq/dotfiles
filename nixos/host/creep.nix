{ nixos-hardware, ... }:
{
  imports = [
    nixos-hardware.nixosModules.lenovo-thinkpad-p16s-amd-gen2

    ../native-linux

    ../laptop/backlight.nix

    ./creep/boot.nix
    ./creep/disk.nix
    ./creep/hardware-configuration.nix
  ];
}
