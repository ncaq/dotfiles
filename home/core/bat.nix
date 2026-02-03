{ pkgs, ... }:
{
  programs.bat = {
    enable = true;
    config = {
      theme = "Solarized (dark)";
      style = "grid,header,snip";
    };
    extraPackages = with pkgs.bat-extras; [
      batdiff
      batgrep
      batman
      batpipe
      batwatch
      prettybat
    ];
  };
}
