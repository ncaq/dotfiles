{ pkgs, ... }:
{
  home.packages = with pkgs; [
    jdt-language-server
  ];
}
