{ pkgs, ... }:
{
  programs = {
    poetry.enable = true;
    pyenv.enable = true;
  };

  home.packages = with pkgs; [
    black
    isort
    jupyter
    pipenv
    pyright
  ];
}
