{
  pkgs,
  lib,
  isWSL,
  ...
}:
# WSL関係のツールを普通のLinux環境にインストールしても、一見コンフリクトしなさそうに見えるが、
# 実際使ってみるとGitHub CLIとかが検知して呼び出しを試みてしまう。
lib.mkIf isWSL {
  home.packages = with pkgs; [
    wslu
  ];
}
