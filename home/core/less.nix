_: {
  programs.less = {
    enable = true;
    options = {
      IGNORE-CASE = true;
      LONG-PROMPT = true;
      RAW-CONTROL-CHARS = true;
    };
  };
  home.sessionVariables = {
    LESSHISTFILE = "-";
  };
}
