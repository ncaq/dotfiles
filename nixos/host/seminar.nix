{ lib, nixos-hardware, ... }:
{
  imports = [
    ../native-linux

    nixos-hardware.nixosModules.common-cpu-amd
    nixos-hardware.nixosModules.common-cpu-amd-pstate
    nixos-hardware.nixosModules.common-gpu-amd
    nixos-hardware.nixosModules.common-pc
    nixos-hardware.nixosModules.common-pc-ssd

    ./seminar/boot.nix
    ./seminar/disk.nix
    ./seminar/hardware-configuration.nix
    ./seminar/machine-info.nix
    ./seminar/ssh.nix
  ];
  # GUIをデフォルトでは起動しない。
  systemd.defaultUnit = lib.mkForce "multi-user.target";
}
