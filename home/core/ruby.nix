{ pkgs, ... }:
{
  home.packages = with pkgs; [
    rubocop
    ruby
    rubyfmt
  ];
}
