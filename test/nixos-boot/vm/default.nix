# NixOS Testのマシンがブートするかを確認するときのVMの設定。
# テスト時には機能しないものなどを無効化したりモックにしたりします。
{ importDirModules, ... }:
{
  imports = importDirModules ./.;
}
