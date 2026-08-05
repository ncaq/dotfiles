{ pkgs, ... }:
let
  marksmanConfig = {
    code_action = {
      toc.enable = false;
    };
  };
  marksmanToml = (pkgs.formats.toml { }).generate "marksman-config" marksmanConfig;
in
{
  xdg.configFile."marksman/config.toml".source = marksmanToml;
}
