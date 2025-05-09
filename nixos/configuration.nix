{ pkgs, ... }:
{
  system.stateVersion = "24.11";

  nix.settings = {
    experimental-features = [
      "flakes"
      "nix-command"
    ];
    max-jobs = "auto";
    cores = 0;
  };

  i18n.defaultLocale = "ja_JP.UTF-8";

  time.timeZone = "Asia/Tokyo";

  programs.zsh.enable = true;

  users.users.ncaq = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
    ];
    shell = pkgs.zsh;
  };
}
