{ pkgs, ... }:
{
  home.packages = with pkgs; [
    cargo
    cargo-outdated
    cargo-watch
    clippy
    license-generator
    rust-analyzer
    rustc
    rustfmt
    rustup
  ];
}
