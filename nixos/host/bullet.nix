{ inputs, ... }:
{
  imports = with inputs; [
    nixos-hardware.nixosModules.common-cpu-amd
    nixos-hardware.nixosModules.common-cpu-amd-pstate
    nixos-hardware.nixosModules.common-gpu-nvidia-nonprime
    nixos-hardware.nixosModules.common-hidpi
    nixos-hardware.nixosModules.common-pc
    nixos-hardware.nixosModules.common-pc-ssd

    ../native-linux

    ../desktop

    ./bullet
  ];
  local.cpuTarget = "AMD Ryzen 9 9950X3D 16-Core Processor";
  hardware.nvidia.open = true;
}
