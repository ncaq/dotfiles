_: {
  services = {
    xserver = {
      enable = true;
      xkb = {
        layout = "us";
        model = "pc104";
        variant = "dvorak";
      };
    };
    libinput.enable = true;
  };
}
