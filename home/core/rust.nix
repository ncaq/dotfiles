{ pkgs, ... }:
{
  home.packages = with pkgs; [
    cargo-outdated
    cargo-watch
    rustup
  ];
}
