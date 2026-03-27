{ config, ... }:
{
  programs = {
    codex = {
      enable = true;
      custom-instructions = config.prompt.codingAgent;
    };
  };
}
