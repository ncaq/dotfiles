{ nixos-hardware, ... }:
{
  hardware.nvidia.open = true;
  imports = [
    nixos-hardware.nixosModules.common-cpu-amd
    nixos-hardware.nixosModules.common-cpu-amd-pstate
    nixos-hardware.nixosModules.common-gpu-nvidia-nonprime
    nixos-hardware.nixosModules.common-hidpi
    nixos-hardware.nixosModules.common-pc
    nixos-hardware.nixosModules.common-pc-ssd

    ./bullet/disko-config.nix
  ];
  boot = {
    loader = {
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot/efi";
      };
      systemd-boot.enable = true;
    };
  };
}
