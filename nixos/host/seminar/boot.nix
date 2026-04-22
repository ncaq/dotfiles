{
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
        configurationLimit = 50;
      };
    };
    initrd = {
      systemd = {
        enable = true;
      };
    };
  };
}
