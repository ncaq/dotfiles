{ pkgs, ... }:
{
  # 別名の`dotnet-sdk`は指す版が変わりうるので、バージョンを明示します。
  # EOLを考えて現行のLTSの10.0だけを入れています。
  home.packages = with pkgs; [
    dotnet-sdk_10
  ];
}
