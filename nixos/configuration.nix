{ pkgs, ... }:
{
  system.stateVersion = "24.11";

  nix.settings = {
    experimental-features = [
      "flakes"
      "nix-command"
    ];
    cores = 0;
    max-jobs = "auto";
    accept-flake-config = true;
    trusted-users = [
      "root"
      "@wheel"
    ];
  };

  i18n.defaultLocale = "ja_JP.UTF-8";

  time.timeZone = "Asia/Tokyo";

  programs.zsh.enable = true;
  services.dbus.packages = [ pkgs.dconf ];
  programs.dconf.enable = true;

  users.users.ncaq = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
    ];
    shell = pkgs.zsh;
  };
}
