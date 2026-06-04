{ pkgs, ... }:
{
  home.packages = with pkgs; [
    openssl
    renovate
    sqlite
    strace
    trash-cli
    wl-clipboard
  ];
}
