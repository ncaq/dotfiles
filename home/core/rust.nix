{ pkgs, ... }:
{
  home.packages = with pkgs; [
    (rust-bin.stable.latest.default.override {
      extensions = [
        "rust-analyzer"
        "rust-src"
      ];
    })

    cargo-outdated
    cargo-watch
    license-generator
  ];
}
