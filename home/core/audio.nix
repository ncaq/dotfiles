{ pkgs, ... }:
{
  home.packages = with pkgs; [
    opusTools
  ];
}
