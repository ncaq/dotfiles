{ pkgs, ... }:
{
  home.packages = with pkgs; [
    cryptsetup
    duperemove
    gnome.gvfs
    ntfs3g
    squashfsTools
  ];
}
