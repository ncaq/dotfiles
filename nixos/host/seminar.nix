{ nixos-hardware, ... }:
{
  imports = [
    ../native-linux

    nixos-hardware.nixosModules.common-cpu-amd
    nixos-hardware.nixosModules.common-cpu-amd-pstate
    nixos-hardware.nixosModules.common-gpu-amd
    nixos-hardware.nixosModules.common-pc
    nixos-hardware.nixosModules.common-pc-ssd
    nixos-hardware.nixosModules.common-pc-hdd

    ./seminar/boot.nix
    ./seminar/disk.nix
    ./seminar/hardware-configuration.nix
  ];
}
