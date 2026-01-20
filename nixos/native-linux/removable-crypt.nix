{
  imports = [ ../../lib/removable-crypt.nix ];

  programs.removable-crypt = {
    enable = true;
    devices = {
      two-thousand.deviceId = "usb-JetFlash_Transcend_32GB_25XSK57XTBIHQODC-0:0-part1";
    };
  };
}
