{ pkgs, ... }:
{
  home.packages = with pkgs; [
    openssl
    renovate
    sbctl
    sqlite
    strace
    trash-cli
    wl-clipboard
  ];
}
