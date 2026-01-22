{ pkgs, ... }:
{
  home.packages = with pkgs; [
    btrfs-progs
    cryptsetup
    duperemove
    exfatprogs
    gnome.gvfs
    ntfs3g
    parted
    squashfsTools
  ];
}
