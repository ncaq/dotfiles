{ pkgs, ... }:
{
  home.packages = with pkgs; [
    license-generator
    openssl
    plantuml
    sqlite
    strace
    trashy
    wl-clipboard
  ];
}
