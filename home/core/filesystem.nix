{ pkgs, ... }:
{
  home.packages = with pkgs; [
    bcache-tools
    btrfs-progs
    cryptsetup
    duperemove
    exfatprogs
    gnome.gvfs
    gocryptfs
    gptfdisk
    ntfs3g
    parted
    samba
    squashfsTools
  ];
}
