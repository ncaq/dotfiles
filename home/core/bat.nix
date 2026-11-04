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
      # prettybatはrustfmtを依存に持ち、
      # そこからnixpkgsのrustcとcargoが閉包に入る。
      # Rustのツールチェインはrustupでも入れているが、
      # それは外部のOSSがrustupを前提にしているからで、
      # このシステムとしてはnixで管理したい。
      # コンパイラが入っていてもセキュリティ上の問題はないので、
      # `withRustFmt = false`で外すことはしない。
      prettybat
    ];
  };
}
