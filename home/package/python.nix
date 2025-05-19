{ pkgs, ... }:
{
  programs = {
    poetry.enable = true;
  };

  home.packages = with pkgs; [
    black
    isort
    pipenv
    pyright
    python3
  ];
}
