{ pkgs, ... }:
{
  programs.bat = {
    enable = true;
    config = {
      theme = "ansi";
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
