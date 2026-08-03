# 壁紙などの作成に向いた16:9の横長構成。
# SDXLが破綻しにくい1280x720で生成して、
# 1.5倍のhires fixでちょうど標準的なモニタサイズの1920x1080が出力される。
{ lib, ... }:
let
  name = "sdxl-wallpaper";
in
{
  local.comfyui.workflows.${name} = import ./lib/standard.nix {
    inherit lib name;
    width = 1280;
    height = 720;
  };
}
