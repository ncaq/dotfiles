_: {
  services = {
    # xserverを有効にするとNixOSの`graphical-desktop.nix`が、
    # `services.speechd.enable`を既定でtrueにして、
    # speech-dispatcherとmbrolaの音声データが閉包に入る。
    # わざわざ無効化するほどではないと判断して既定のままにしている。
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
