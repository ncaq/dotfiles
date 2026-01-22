{
  imports = [ ../../lib/removable-crypt.nix ];

  programs.removable-crypt = {
    enable = true;
    devices = {
      gideon.deviceId = "usb-USB_SanDisk_3.2Gen1_03005417112725151804-0:0-part1";
      two-thousand.deviceId = "usb-JetFlash_Transcend_32GB_25XSK57XTBIHQODC-0:0-part1";
    };
  };
}
