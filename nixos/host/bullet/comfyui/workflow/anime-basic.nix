# txt2imgの基本形。
{ lib, ... }:
let
  name = "anime-basic";
  inherit (import ./lib/builder.nix { inherit lib; })
    mkNode
    mkInput
    mkOutput
    mkAppInput
    mkAppInputWith
    mkWorkflow
    mkFilenamePrefix
    promptNodes
    promptLinks
    ;
in
{
  local.comfyui.workflows.${name} = mkWorkflow {
    app = {
      inputs = [
        (mkAppInputWith 2 "text" {
          height = 160;
          description = "生成する画像の内容";
        })
        (mkAppInputWith 3 "text" {
          height = 120;
          description = "画像に含めたくない内容";
        })
        (mkAppInput 4 "width")
        (mkAppInput 4 "height")
        (mkAppInput 5 "seed")
      ];
      outputs = [ 7 ];
    };
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
        order = 6;
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
        order = 7;
        inputs = [ (mkInput "images" "IMAGE" 9) ];
        widgets = [ (mkFilenamePrefix name) ];
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
