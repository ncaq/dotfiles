{ inputs, ... }:
{
  imports = with inputs; [
    nixos-hardware.nixosModules.lenovo-thinkpad-p16s-amd-gen2

    ../native-linux

    ../client
    ../laptop

    ./creep
  ];
  local.cpuTarget = "AMD Ryzen 5 PRO 7540U w/ Radeon 740M Graphics";
}
