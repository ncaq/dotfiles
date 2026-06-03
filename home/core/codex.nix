{ pkgs-unstable, config, ... }:
{
  programs = {
    codex = {
      enable = true;
      package = pkgs-unstable.codex;
      context = config.prompt.codingAgent;
    };
  };
}
