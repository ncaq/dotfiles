{ pkgs, ... }:
{
  home.packages = with pkgs; [
    android-tools
    ddcutil
    efibootmgr
    i2c-tools
    lshw
    pciutils
    rwedid
    usbutils
    v4l-utils
  ];
}
