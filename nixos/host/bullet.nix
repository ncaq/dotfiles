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
      systemd-boot = {
        enable = true;
        consoleMode = "auto";
        xbootldrMountPoint = "/boot";
        edk2-uefi-shell.enable = true;
        # 仕事用Windowsを最上位に表示し、上キーで移動できるようにする。
        windows = {
          "work" = {
            title = "Windows 11 Work";
            efiDeviceHandle = "HD0b";
            sortKey = "a_windows_work";
          };
          "game" = {
            title = "Windows 11 Game";
            efiDeviceHandle = "HD1b";
            sortKey = "b_windows_game";
          };
        };
      };
    };
  };
  hardware.nvidia.open = true;
}
