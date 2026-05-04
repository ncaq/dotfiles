{ pkgs, ... }:
{
  home.packages = with pkgs; [
    openssl
    plantuml
    sqlite
    strace
    trash-cli
    wl-clipboard
  ];
}
