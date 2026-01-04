{ nixos-hardware, ... }:
{
  imports = [
    nixos-hardware.nixosModules.lenovo-thinkpad-p16s-amd-gen2

    ../native-linux

    ../laptop

    ./creep
  ];
}
