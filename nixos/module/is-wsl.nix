# WSL環境判定のオプションを提供するモジュール
{ lib, ... }:
{
  options.isWSL = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Whether this system is running on WSL";
  };
}
