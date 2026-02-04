{ pkgs, ... }:
{
  programs = {
    poetry.enable = true;
  };

  home.packages = with pkgs; [
    black
    isort
    pipenv
    pipx
    pyright
    python3
    python3Packages.pip
  ];
}
