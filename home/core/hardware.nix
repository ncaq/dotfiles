{ pkgs, ... }:
{
  home.packages = with pkgs; [
    android-tools
    ddcutil
    efibootmgr
    i2c-tools
    lshw
    nvtopPackages.full
    pciutils
    rwedid
    usbutils
    v4l-utils
  ];
}
