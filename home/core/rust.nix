{ pkgs, ... }:
{
  home.packages = with pkgs; [
    cargo
    cargo-outdated
    cargo-watch
    clippy
    rust-analyzer
    rustc
    rustfmt
    rustup
  ];
}
