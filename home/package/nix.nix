# Nix言語の編集・開発を補助するパッケージ。
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    alejandra
    nil
    nix-diff
    nix-prefetch
    nixfmt-rfc-style
  ];
}
