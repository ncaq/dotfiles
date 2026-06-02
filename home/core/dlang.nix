{ pkgs, ... }:
{
  # 現在dmdのビルドに失敗するので、
  # とりあえずldcだけをインストールしておきます。
  # PRは既に出ています。
  # [D 2.112.1 by jtbx](https://github.com/NixOS/nixpkgs/pull/479273)
  home.packages = with pkgs; [
    ldc
  ];
}
