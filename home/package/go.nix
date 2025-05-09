{ config, ... }:
{
  programs.go = {
    enable = true;
    goPath = "${config.home.homeDirectory}/.go";
  };

  home.sessionPath = [
    "${config.home.homeDirectory}/.go/bin"
  ];
}
