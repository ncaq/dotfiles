{ pkgs, ... }:
{
  home.packages = with pkgs; [
    helvum
  ];
}
