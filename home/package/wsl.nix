{ pkgs, ... }:
{
  home.packages = with pkgs; [
    wslu
  ];
}
