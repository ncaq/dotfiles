{ pkgs, ... }:
{
  home.packages = with pkgs; [
    fd
    file
    findutils
    plocate
    tree
  ];
}
