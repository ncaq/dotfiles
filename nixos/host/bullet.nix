{ nixos-hardware, ... }:
{
  imports = [
    ../native-linux

    ../desktop/dpms.nix

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
        default = "saved";
        extraEntries = ''
          menuentry "Windows Game" {
            savedefault
            insmod part_gpt
            insmod fat
            insmod search_fs_uuid
            insmod chain
            search --fs-uuid --set=root 8E7A-6494
            chainloader /EFI/Microsoft/Boot/bootmgfw.efi
          }
          menuentry "Windows Work" {
            savedefault
            insmod part_gpt
            insmod fat
            insmod search_fs_uuid
            insmod chain
            search --fs-uuid --set=root CE5B-C127
            chainloader /EFI/Microsoft/Boot/bootmgfw.efi
          }
        '';
      };
    };
  };
  hardware.nvidia.open = true;
}
