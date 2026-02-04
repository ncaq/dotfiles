{ config, ... }:
{
  home.sessionPath = [
    "${config.home.homeDirectory}/.local/bin"
  ];
}
