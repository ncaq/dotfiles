{ pkgs, ... }:
{
  home.packages = with pkgs; [
    rubocop
    ruby
    ruby-lsp
    rubyfmt
  ];
}
