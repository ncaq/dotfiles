{ pkgs, ... }:
{
  home.packages = with pkgs; [
    sourcekit-lsp
  ];
}
