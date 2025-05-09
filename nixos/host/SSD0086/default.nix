{ ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "SSD0086";

  wsl.enable = true;
}
