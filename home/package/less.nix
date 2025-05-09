{ ... }:
{
  programs.less = {
    enable = true;
  };
  home.sessionVariables = {
    LESS = "--ignore-case --long-prompt --RAW-CONTROL-CHARS";
    LESSHISTFILE = "-";
  };
}
