{ dot-xmonad, ... }:
{
  xsession = {
    enable = true;
    windowManager.command = "xmonad-launch";
  };

  home.packages = [
    dot-xmonad
  ];
}
