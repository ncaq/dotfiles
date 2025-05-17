{ config, ... }:
{
  targets.genericLinux.enable = true;
  home.sessionPath = [
    "${config.home.homeDirectory}/.local/bin"
  ];
}
