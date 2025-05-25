{ pkgs, ... }:
{
  programs.dconf.enable = true;
  services.dbus.packages = [ pkgs.dconf ];
}
