{ pkgs, ... }:
{
  home.packages = with pkgs; [
    btrfs-progs
    cryptsetup
    duperemove
    exfat
    exfatprogs
    gnome.gvfs
    ntfs3g
    parted
    squashfsTools
  ];
}
