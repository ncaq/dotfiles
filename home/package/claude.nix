{ pkgs-unstable, config, ... }:
{
  home.packages = [
    pkgs-unstable.claude-code
  ];

  home.file = {
    ".claude" = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/claude";
    };
  };
}
