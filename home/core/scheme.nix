{ pkgs, ... }:
{
  home.packages = with pkgs; [
    gauche
  ];
}
