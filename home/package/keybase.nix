{ pkgs, ... }:
{
  services.keybase.enable = true;
  home.packages = with pkgs; [
    kbfs
    keybase-gui
  ];
}
