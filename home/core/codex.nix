{ pkgs-unstable, config, ... }:
{
  programs = {
    codex = {
      enable = true;
      package = pkgs-unstable.codex;
      custom-instructions = config.prompt.codingAgent;
    };
  };
}
