{
  pkgs,
  lib,
  isWSL,
  ...
}:
# WSL関係のツールを普通のLinux環境にインストールしても一見コンフリクトしなさそうだと思うが、
# 実際使ってみるとGitHub CLIとかが存在を検知して呼び出しを試みてしまうため、
# そもそもWSLじゃない環境ではインストールしないようにする。
lib.mkIf isWSL {
  home.packages = with pkgs; [
    wslu
  ];
}
