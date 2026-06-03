{ pkgs, ... }:
{
  home.packages = with pkgs; [
    flac
    opus-tools
  ];
}
