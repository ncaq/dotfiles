{ pkgs, ... }:
{
  home.packages = with pkgs; [
    openssl
    plantuml
    renovate
    sqlite
    strace
    trash-cli
    wl-clipboard
  ];
}
