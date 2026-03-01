{ pkgs, ... }:
{
  home.packages = with pkgs; [
    csharp-ls
  ];
}
