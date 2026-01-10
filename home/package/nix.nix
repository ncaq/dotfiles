# Nix言語の編集・開発を補助するパッケージ。
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    nil
    nix-diff
    nixfmt-rfc-style
  ];
}
