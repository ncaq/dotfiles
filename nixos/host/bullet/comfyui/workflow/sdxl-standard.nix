# キャラクター向けのポートレート構成。
# SDXLのポートレートバケット解像度で生成して、
# 1.5倍のhires fixで1248x1824が出力される。
{ lib, ... }:
let
  name = "sdxl-standard";
in
{
  local.comfyui.workflows.${name} = import ./lib/standard.nix {
    inherit lib name;
    width = 832;
    height = 1216;
  };
}
