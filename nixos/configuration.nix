{ pkgs, hostName, ... }:
{
  system.stateVersion = "25.05";

  networking.hostName = hostName;

  i18n.defaultLocale = "ja_JP.UTF-8";

  time.timeZone = "Asia/Tokyo";

  programs = {
    dconf.enable = true;
    nix-ld.enable = true;
    zsh.enable = true;
  };

  services.dbus.packages = [ pkgs.dconf ];

  users.users.ncaq = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "input"
    ];
    shell = pkgs.zsh;
  };

  imports = [
    ./nix-settings.nix
    ./locate.nix
    ./uinput.nix
  ];
}
