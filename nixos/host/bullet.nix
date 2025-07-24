{ nixos-hardware, ... }:
{
  imports = [
    ../native-linux

    nixos-hardware.nixosModules.common-cpu-amd
    nixos-hardware.nixosModules.common-cpu-amd-pstate
    nixos-hardware.nixosModules.common-gpu-nvidia-nonprime
    nixos-hardware.nixosModules.common-hidpi
    nixos-hardware.nixosModules.common-pc
    nixos-hardware.nixosModules.common-pc-ssd

    ./bullet/disk.nix
    ./bullet/hardware-configuration.nix
  ];
  boot = {
    loader = {
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/efi";
      };
      timeout = 1;
      grub = {
        enable = true;
        device = "nodev";
        efiSupport = true;
        gfxmodeEfi = "1024x768";
        extraEntries = ''
          menuentry "Windows Game" {
            insmod part_gpt
            insmod fat
            insmod chain
            set root='hd0,gpt1'
            chainloader /efi/Microsoft/Boot/bootmgfw.efi
          }
          menuentry "Windows Work" {
            insmod part_gpt
            insmod fat
            insmod chain
            set root='hd1,gpt1'
            chainloader /efi/Microsoft/Boot/bootmgfw.efi
          }
        '';
      };
    };
  };
  hardware.nvidia.open = true;
}
