# diskoのデバイス定義を無効化。
# VMではvirtualisationモジュールがファイルシステムを管理します。
{ lib, ... }:
{
  disko.devices = lib.mkForce { };
}
