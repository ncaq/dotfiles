# キャラクター向けのポートレート構成。
# SDXLのポートレートバケット解像度で生成して、
# 1.5倍のhires fixで1248x1824が出力される。
{ lib, ... }:
{
  local.comfyui.workflows.anime-standard = import ./lib/standard.nix {
    inherit lib;
    width = 832;
    height = 1216;
    filenamePrefix = "anime-standard";
  };
}
