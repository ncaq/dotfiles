# Animaによる通常のimg2img画像編集。
# 入力画像をQwen-Image VAEでlatent化し、denoiseで元画像を残す強さを調整する。
# 指示箇所だけを変更するqwen-editと違い、画像全体をプロンプトに沿って描き直す。
#
# denoiseの目安:
# 0.2から0.35で色や線を維持した微調整、
# 0.35から0.55で一般的な描き直し、
# 0.55から0.75で大幅なスタイルや内容の変更。
{ lib, ... }:
let
  name = "anima-edit";
  inherit (import ./lib/builder.nix { inherit lib; })
    mkNode
    mkInput
    mkOutput
    mkLoraLoader
    mkAppInput
    mkAppInputWith
    mkWorkflow
    mkFilenamePrefix
    seedWidgets
    ;
in
{
  local.comfyui.workflows.${name} = mkWorkflow {
    app = {
      inputs = [
        (mkAppInput 6 "image")
        (mkAppInput 1 "unet_name")
        (mkAppInputWith 4 "text" {
          height = 180;
          description = "画像をどのように描き直すか";
        })
        (mkAppInputWith 5 "text" {
          height = 140;
          description = "画像に含めたくない内容";
        })
        (mkAppInputWith 9 "denoise" {
          description = "元画像を変える強さ。0.3で微調整、0.5で描き直し、0.7で大幅に変更";
        })
        (mkAppInput 9 "seed")
        (mkAppInput 7 "megapixels")
      ];
      outputs = [ 12 ];
    };
    nodes = [
      (mkNode {
        id = 1;
        type = "UNETLoader";
        pos = [
          (-40)
          20
        ];
        size = [
          385
          82
        ];
        order = 0;
        outputs = [ (mkOutput "MODEL" "MODEL" [ 1 ]) ];
        widgets = [
          "anima-aesthetic-v1.1.safetensors"
          "default"
        ];
      })
      (mkNode {
        id = 2;
        type = "CLIPLoader";
        pos = [
          (-40)
          180
        ];
        size = [
          385
          106
        ];
        order = 1;
        outputs = [
          (mkOutput "CLIP" "CLIP" [
            2
            3
          ])
        ];
        widgets = [
          "qwen_3_06b_base.safetensors"
          "stable_diffusion"
          "default"
        ];
      })
      (mkNode {
        id = 3;
        type = "VAELoader";
        pos = [
          (-40)
          360
        ];
        size = [
          385
          58
        ];
        order = 2;
        outputs = [
          (mkOutput "VAE" "VAE" [
            8
            9
          ])
        ];
        widgets = [ "qwen_image_vae.safetensors" ];
      })
      # 通常のAnima LoRAはMODELだけへ適用する。
      (mkLoraLoader {
        id = 10;
        title = "Anima LoRA (MODEL only)";
        pos = [
          (-40)
          500
        ];
        order = 3;
        modelLink = 1;
        modelLinks = [ 4 ];
      })
      (mkNode {
        id = 4;
        type = "CLIPTextEncode";
        title = "Positive Prompt";
        pos = [
          420
          20
        ];
        size = [
          420
          180
        ];
        order = 4;
        inputs = [ (mkInput "clip" "CLIP" 2) ];
        outputs = [ (mkOutput "CONDITIONING" "CONDITIONING" [ 5 ]) ];
        widgets = [ "masterpiece, best quality, solo, 1girl" ];
      })
      (mkNode {
        id = 5;
        type = "CLIPTextEncode";
        title = "Negative Prompt";
        pos = [
          420
          280
        ];
        size = [
          420
          180
        ];
        order = 5;
        inputs = [ (mkInput "clip" "CLIP" 3) ];
        outputs = [ (mkOutput "CONDITIONING" "CONDITIONING" [ 6 ]) ];
        widgets = [
          "worst quality, low quality, artist name, blurry, jpeg artifacts, chromatic aberration"
        ];
      })
      (mkNode {
        id = 6;
        type = "LoadImage";
        title = "編集する画像";
        pos = [
          420
          550
        ];
        size = [
          340
          314
        ];
        order = 6;
        outputs = [
          (mkOutput "IMAGE" "IMAGE" [ 7 ])
          (mkOutput "MASK" "MASK" [ ])
        ];
        widgets = [
          "example.png"
          "image"
        ];
      })
      # アスペクト比を維持して約1MPへスケールし、Animaの要求する16の倍数へ丸める。
      (mkNode {
        id = 7;
        type = "ImageScaleToTotalPixels";
        title = "Anima生成解像度へスケール";
        pos = [
          820
          550
        ];
        size = [
          315
          130
        ];
        order = 7;
        inputs = [ (mkInput "image" "IMAGE" 7) ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 10 ]) ];
        widgets = [
          "lanczos"
          1.0
          16
        ];
      })
      (mkNode {
        id = 8;
        type = "VAEEncode";
        pos = [
          1190
          550
        ];
        size = [
          210
          46
        ];
        order = 8;
        inputs = [
          (mkInput "pixels" "IMAGE" 10)
          (mkInput "vae" "VAE" 8)
        ];
        outputs = [ (mkOutput "LATENT" "LATENT" [ 11 ]) ];
      })
      (mkNode {
        id = 9;
        type = "KSampler";
        pos = [
          1460
          180
        ];
        size = [
          315
          262
        ];
        order = 9;
        inputs = [
          (mkInput "model" "MODEL" 4)
          (mkInput "positive" "CONDITIONING" 5)
          (mkInput "negative" "CONDITIONING" 6)
          (mkInput "latent_image" "LATENT" 11)
        ];
        outputs = [ (mkOutput "LATENT" "LATENT" [ 12 ]) ];
        widgets = seedWidgets ++ [
          40
          4
          "euler"
          "simple"
          0.5
        ];
      })
      (mkNode {
        id = 11;
        type = "VAEDecode";
        pos = [
          1830
          180
        ];
        size = [
          210
          46
        ];
        order = 10;
        inputs = [
          (mkInput "samples" "LATENT" 12)
          (mkInput "vae" "VAE" 9)
        ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 13 ]) ];
      })
      (mkNode {
        id = 12;
        type = "SaveImage";
        pos = [
          2100
          180
        ];
        size = [
          420
          470
        ];
        order = 11;
        inputs = [ (mkInput "images" "IMAGE" 13) ];
        widgets = [ (mkFilenamePrefix name) ];
      })
    ];
    links = [
      [
        1
        1
        0
        10
        0
        "MODEL"
      ]
      [
        2
        2
        0
        4
        0
        "CLIP"
      ]
      [
        3
        2
        0
        5
        0
        "CLIP"
      ]
      [
        4
        10
        0
        9
        0
        "MODEL"
      ]
      [
        5
        4
        0
        9
        1
        "CONDITIONING"
      ]
      [
        6
        5
        0
        9
        2
        "CONDITIONING"
      ]
      [
        7
        6
        0
        7
        0
        "IMAGE"
      ]
      [
        8
        3
        0
        8
        1
        "VAE"
      ]
      [
        9
        3
        0
        11
        1
        "VAE"
      ]
      [
        10
        7
        0
        8
        0
        "IMAGE"
      ]
      [
        11
        8
        0
        9
        3
        "LATENT"
      ]
      [
        12
        9
        0
        11
        0
        "LATENT"
      ]
      [
        13
        11
        0
        12
        0
        "IMAGE"
      ]
    ];
  };
}
