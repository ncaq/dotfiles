# Nix言語に関係するパッケージ。
# Nixエコシステムまではあまりカバーしない。
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    alejandra
    nil
    nixfmt-rfc-style
  ];
}
