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
  home.packages = with pkgs; [ marksman ];

  xdg.configFile."marksman/config.toml".source = marksmanToml;
}
