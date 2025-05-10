{ config, ... }:
{
  programs.go = {
    enable = true;
    goPath = ".go";
  };

  home.sessionPath = [
    "${config.home.homeDirectory}/.go/bin"
  ];
}
