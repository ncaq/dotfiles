# img2imgによる画像編集。
# 既存の画像を読み込んでVAEでlatentへ変換して、
# 低めのdenoiseで再サンプリングすることで、
# 元画像の構図を残したままプロンプトに沿って描き直す。
#
# denoiseの目安:
# 0.3前後で色味や質感の微調整、
# 0.5前後で描き込みの変更、
# 0.7以上で構図だけ借りた大胆な変更。
{ lib, ... }:
let
  inherit (import ./lib/builder.nix { inherit lib; })
    mkNode
    mkInput
    mkOutput
    mkWorkflow
    promptNodes
    promptBaseLinks
    ;
in
{
  local.comfyui.workflows.anime-edit = mkWorkflow {
    nodes =
      promptNodes {
        # EmptyLatentImageの代わりにLoadImage+VAEEncodeからLATENTを供給する。
        withEmptyLatent = false;
        samplerOrder = 5;
        denoise = 0.5;
        # VAEEncodeへ。
        extraVaeLinks = [ 13 ];
      }
      ++ [
        (mkNode {
          id = 4;
          type = "LoadImage";
          pos = [
            (-40)
            500
          ];
          size = [
            340
            314
          ];
          order = 3;
          outputs = [
            (mkOutput "IMAGE" "IMAGE" [ 12 ])
            (mkOutput "MASK" "MASK" [ ])
          ];
          widgets = [
            "example.png"
            "image"
          ];
        })
        (mkNode {
          id = 8;
          type = "VAEEncode";
          pos = [
            420
            500
          ];
          size = [
            210
            46
          ];
          order = 4;
          inputs = [
            (mkInput "pixels" "IMAGE" 12)
            (mkInput "vae" "VAE" 13)
          ];
          outputs = [ (mkOutput "LATENT" "LATENT" [ 6 ]) ];
        })
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
          widgets = [ "anime-edit" ];
        })
      ];
    links = promptBaseLinks ++ [
      [
        6
        8
        0
        5
        3
        "LATENT"
      ]
      [
        9
        6
        0
        7
        0
        "IMAGE"
      ]
      [
        12
        4
        0
        8
        0
        "IMAGE"
      ]
      [
        13
        1
        2
        8
        1
        "VAE"
      ]
    ];
  };
}
