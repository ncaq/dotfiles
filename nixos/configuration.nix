{ ... }:
{
  system.stateVersion = "25.05";

  i18n.defaultLocale = "ja_JP.UTF-8";
  time.timeZone = "Asia/Tokyo";

  console.keyMap = "dvorak";

  programs = {
    nix-ld.enable = true;
    zsh.enable = true;
  };

  imports = [ ./core ];
}
