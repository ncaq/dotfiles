{ nixos-hardware, ... }:
{
  imports = [
    nixos-hardware.nixosModules.common-cpu-amd
    nixos-hardware.nixosModules.common-cpu-amd-pstate
    nixos-hardware.nixosModules.common-gpu-nvidia-nonprime
    nixos-hardware.nixosModules.common-hidpi
    nixos-hardware.nixosModules.common-pc
    nixos-hardware.nixosModules.common-pc-ssd

    ../native-linux

    ../desktop/dpms.nix

    ./bullet/boot.nix
    ./bullet/disk.nix
    ./bullet/hardware-configuration.nix
  ];
  hardware.nvidia.open = true;
}
