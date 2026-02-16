{ pkgs, ... }:
{
  home.packages = with pkgs; [
    flac
    opusTools
  ];
}
