{ pkgs, ... }:
{
  home.packages = with pkgs; [
    gradle
    kotlin
    kotlin-language-server
  ];
}
