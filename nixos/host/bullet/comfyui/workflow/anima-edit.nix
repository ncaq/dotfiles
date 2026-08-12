# Animaによる通常のimg2img画像編集。
# 入力画像をQwen-Image VAEでlatent化し、start_at_stepで元画像を残す強さを調整する。
# 入力画像はアスペクト比を維持して約1MPへスケールし、
# Animaのlatent寸法制約を満たすように各辺を16の倍数へ揃える。
# 目標画素数はApp Modeのmegapixels入力で変更できる。
# 指示箇所だけを変更するqwen-editと違い、画像全体をプロンプトに沿って描き直す。
#
# 変える強さはKSamplerAdvancedの`start_at_step`で指定する。
# 全30ステップのどこから流すかという指定なので、
# 大きいほど元画像が残り、実行するステップ数もその分だけ減る。
# denoiseと違って強さとステップ数が連動するため、
# 強さを変えてもステップ数を付け替えずに済む。
#
# start_at_stepの目安(全30ステップ):
# 20から24で色や線を維持した微調整(denoise 0.2から0.35相当)、
# 14から20で一般的な描き直し(denoise 0.35から0.55相当)、
# 8から14で大幅なスタイルや内容の変更(denoise 0.55から0.75相当)。
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
    animaSizeMultiple
    animaBaseSteps
    startStepForDenoise
    ;
  # App Modeから変えられる強さのデフォルト値。
  # denoise 0.5相当の位置から流す。
  denoise = 0.5;
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
        (mkAppInputWith 9 "start_at_step" {
          description = "全30ステップ中のどこから描き直すか。21で微調整、15で描き直し、9で大幅に変更";
        })
        (mkAppInput 9 "noise_seed")
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
      # Anima公式はLLM adapterを学習しないよう推奨しているため、
      # 通常のAnima LoRAはMODELだけへ適用してCLIPを素通しする。
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
      # ImageScaleToTotalPixelsのresolution_stepsはComfyUI 0.28.2の定義に合わせている。
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
          "lanczos" # upscale_method
          1.0 # megapixels
          animaSizeMultiple # resolution_steps
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
        type = "KSamplerAdvanced";
        pos = [
          1460
          180
        ];
        size = [
          315
          334
        ];
        order = 9;
        inputs = [
          (mkInput "model" "MODEL" 4)
          (mkInput "positive" "CONDITIONING" 5)
          (mkInput "negative" "CONDITIONING" 6)
          (mkInput "latent_image" "LATENT" 11)
        ];
        outputs = [ (mkOutput "LATENT" "LATENT" [ 12 ]) ];
        widgets = [
          "enable"
        ] # add_noise
        ++ seedWidgets
        ++ [
          animaBaseSteps # steps
          4 # cfg
          "euler" # sampler_name
          "simple" # scheduler
          (startStepForDenoise animaBaseSteps denoise) # start_at_step
          10000 # end_at_step(実際の終端はstepsで決まる)
          "disable" # return_with_leftover_noise
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
