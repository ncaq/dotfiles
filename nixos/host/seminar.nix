{ lib, inputs, ... }:
{
  imports = with inputs; [
    nixos-hardware.nixosModules.common-cpu-amd
    nixos-hardware.nixosModules.common-cpu-amd-pstate
    nixos-hardware.nixosModules.common-gpu-amd
    nixos-hardware.nixosModules.common-pc
    nixos-hardware.nixosModules.common-pc-ssd

    microvm.nixosModules.host

    ../native-linux

    ./seminar
  ];
  # GUIをデフォルトでは起動しない。
  systemd.defaultUnit = lib.mkForce "multi-user.target";
}
