{ pkgs, ... }:
{
  home.packages = with pkgs; [
    rakudo
  ];
}
