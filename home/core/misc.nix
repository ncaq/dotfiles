{ pkgs, ... }:
{
  home.packages = with pkgs; [
    license-generator
    openssl
    plantuml
    sqlite
    strace
    trash-cli
    wl-clipboard
  ];
}
