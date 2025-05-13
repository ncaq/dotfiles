{ pkgs, lib, ... }:
{
  home.packages = with pkgs; [
    cargo-outdated
    cargo-watch
    license-generator
    rustup
  ];

  home.activation.setupRustup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.rustup}/bin/rustup default stable
  '';
}
