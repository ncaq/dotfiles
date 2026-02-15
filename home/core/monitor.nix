{ pkgs, ... }:
{
  home.packages = with pkgs; [
    atop
    htop
    iotop
    lsof
    procps
    pstree
    sysstat
  ];
}
