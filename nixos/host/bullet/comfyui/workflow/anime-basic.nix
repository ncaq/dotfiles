# txt2imgの基本形。
{ lib, ... }:
let
  inherit (import ./lib/builder.nix { inherit lib; })
    mkNode
    mkInput
    mkOutput
    mkWorkflow
    promptNodes
    promptLinks
    ;
in
{
  local.comfyui.workflows.anime-basic = mkWorkflow {
    nodes = promptNodes { } ++ [
      (mkNode {
        id = 6;
        type = "VAEDecode";
        pos = [
          1290
          200
        ];
        size = [
          210
          46
        ];
        order = 5;
        inputs = [
          (mkInput "samples" "LATENT" 7)
          (mkInput "vae" "VAE" 8)
        ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 9 ]) ];
      })
      (mkNode {
        id = 7;
        type = "SaveImage";
        pos = [
          1560
          200
        ];
        size = [
          420
          470
        ];
        order = 6;
        inputs = [ (mkInput "images" "IMAGE" 9) ];
        widgets = [ "anime-basic" ];
      })
    ];
    links = promptLinks ++ [
      [
        9
        6
        0
        7
        0
        "IMAGE"
      ]
    ];
  };
}
