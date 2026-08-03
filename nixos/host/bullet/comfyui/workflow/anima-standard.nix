# Animaによるtxt2imgの標準構成。
# LoRA、1.5倍のhires fix、FaceDetailerを一つのパイプラインで適用する。
# 高品質と一貫性を優先してAesthetic v1.1をデフォルトにする。
# Baseは多様性とLoRA利用向けにモデル一覧から切り替えられる。
# FaceDetailerのwidgets_valuesはComfyUI-Impact-Pack 8.28の定義に合わせている。
{ lib, ... }:
let
  name = "anima-standard";
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
        (mkAppInput 1 "unet_name")
        (mkAppInputWith 4 "text" {
          height = 180;
          description = "生成する画像の内容";
        })
        (mkAppInputWith 5 "text" {
          height = 140;
          description = "画像に含めたくない内容";
        })
        (mkAppInputWith 20 "width" {
          description = "生成幅。Anima向けに16の倍数へ切り下げる";
        })
        (mkAppInputWith 20 "height" {
          description = "生成高。Anima向けに16の倍数へ切り下げる";
        })
        (mkAppInput 7 "seed")
        (mkAppInput 7 "steps")
        (mkAppInput 7 "cfg")
        (mkAppInput 7 "sampler_name")
        (mkAppInput 7 "scheduler")
      ];
      outputs = [ 18 ];
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
        outputs = [ (mkOutput "MODEL" "MODEL" [ 10 ]) ];
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
            22
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
            28
            19
            23
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
        modelLink = 10;
        modelLinks = [
          1
          14
          21
        ];
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
        outputs = [
          (mkOutput "CONDITIONING" "CONDITIONING" [
            4
            15
            24
          ])
        ];
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
        outputs = [
          (mkOutput "CONDITIONING" "CONDITIONING" [
            5
            16
            25
          ])
        ];
        widgets = [
          "worst quality, low quality, artist name, blurry, jpeg artifacts, chromatic aberration"
        ];
      })
      (mkNode {
        id = 20;
        type = "AlignImageDimensions";
        title = "Anima生成寸法を16の倍数へ整列";
        pos = [
          420
          550
        ];
        size = [
          315
          130
        ];
        order = 6;
        outputs = [
          (mkOutput "width" "INT" [ 30 ])
          (mkOutput "height" "INT" [ 31 ])
        ];
        widgets = [
          1024 # width
          1024 # height
          16 # multiple
        ];
      })
      (mkNode {
        id = 6;
        type = "EmptyLatentImage";
        pos = [
          820
          550
        ];
        size = [
          315
          106
        ];
        order = 7;
        inputs = [
          (
            mkInput "width" "INT" 30
            // {
              widget = {
                name = "width";
              };
            }
          )
          (
            mkInput "height" "INT" 31
            // {
              widget = {
                name = "height";
              };
            }
          )
        ];
        outputs = [ (mkOutput "LATENT" "LATENT" [ 6 ]) ];
        widgets = [
          1024
          1024
          1
        ];
      })
      (mkNode {
        id = 9;
        type = "UpscaleModelLoader";
        pos = [
          1290
          20
        ];
        size = [
          315
          58
        ];
        order = 8;
        outputs = [ (mkOutput "UPSCALE_MODEL" "UPSCALE_MODEL" [ 9 ]) ];
        widgets = [ "4x-AnimeSharp.safetensors" ];
      })
      (mkNode {
        id = 16;
        type = "UltralyticsDetectorProvider";
        pos = [
          2310
          20
        ];
        size = [
          315
          78
        ];
        order = 9;
        outputs = [
          (mkOutput "BBOX_DETECTOR" "BBOX_DETECTOR" [ 26 ])
          (mkOutput "SEGM_DETECTOR" "SEGM_DETECTOR" [ ])
        ];
        widgets = [ "bbox/face_yolov9c.pt" ];
      })
      (mkNode {
        id = 7;
        type = "KSampler";
        pos = [
          920
          180
        ];
        size = [
          315
          262
        ];
        order = 10;
        inputs = [
          (mkInput "model" "MODEL" 1)
          (mkInput "positive" "CONDITIONING" 4)
          (mkInput "negative" "CONDITIONING" 5)
          (mkInput "latent_image" "LATENT" 6)
        ];
        outputs = [ (mkOutput "LATENT" "LATENT" [ 7 ]) ];
        widgets = seedWidgets ++ [
          30 # steps
          4 # cfg
          "euler" # sampler_name
          "simple" # scheduler
          1 # denoise
        ];
      })
      (mkNode {
        id = 8;
        type = "VAEDecode";
        pos = [
          1290
          180
        ];
        size = [
          210
          46
        ];
        order = 11;
        inputs = [
          (mkInput "samples" "LATENT" 7)
          (mkInput "vae" "VAE" 8)
        ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 11 ]) ];
      })
      (mkNode {
        id = 11;
        type = "ImageUpscaleWithModel";
        pos = [
          1560
          180
        ];
        size = [
          240
          46
        ];
        order = 12;
        inputs = [
          (mkInput "upscale_model" "UPSCALE_MODEL" 9)
          (mkInput "image" "IMAGE" 11)
        ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 12 ]) ];
      })
      # 4倍アップスケール後に0.375倍へ縮小し、全体で1.5倍にする。
      (mkNode {
        id = 12;
        type = "ImageScaleBy";
        pos = [
          1560
          280
        ];
        size = [
          315
          82
        ];
        order = 13;
        inputs = [ (mkInput "image" "IMAGE" 12) ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 29 ]) ];
        widgets = [
          "area" # upscale_method
          0.375 # scale_by
        ];
      })
      # 1.5倍後の各辺を中央cropし、Animaが要求する16の倍数へ揃える。
      (mkNode {
        id = 19;
        type = "AlignImageSize";
        pos = [
          1560
          420
        ];
        size = [
          210
          58
        ];
        order = 14;
        inputs = [ (mkInput "image" "IMAGE" 29) ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 13 ]) ];
        widgets = [ 16 ];
      })
      (mkNode {
        id = 13;
        type = "VAEEncode";
        pos = [
          1560
          560
        ];
        size = [
          210
          46
        ];
        order = 15;
        inputs = [
          (mkInput "pixels" "IMAGE" 13)
          (mkInput "vae" "VAE" 28)
        ];
        outputs = [ (mkOutput "LATENT" "LATENT" [ 17 ]) ];
      })
      (mkNode {
        id = 14;
        type = "KSampler";
        title = "Hires Fix";
        pos = [
          1940
          180
        ];
        size = [
          315
          262
        ];
        order = 16;
        inputs = [
          (mkInput "model" "MODEL" 14)
          (mkInput "positive" "CONDITIONING" 15)
          (mkInput "negative" "CONDITIONING" 16)
          (mkInput "latent_image" "LATENT" 17)
        ];
        outputs = [ (mkOutput "LATENT" "LATENT" [ 18 ]) ];
        widgets = seedWidgets ++ [
          18 # steps
          4 # cfg
          "euler" # sampler_name
          "simple" # scheduler
          # 元の構図と顔を維持しながらアップスケーラの細部だけを再生成する。
          0.3 # denoise
        ];
      })
      (mkNode {
        id = 15;
        type = "VAEDecode";
        pos = [
          2310
          180
        ];
        size = [
          210
          46
        ];
        order = 17;
        inputs = [
          (mkInput "samples" "LATENT" 18)
          (mkInput "vae" "VAE" 19)
        ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 20 ]) ];
      })
      (mkNode {
        id = 17;
        type = "FaceDetailer";
        pos = [
          2580
          180
        ];
        size = [
          400
          800
        ];
        order = 18;
        inputs = [
          (mkInput "image" "IMAGE" 20)
          (mkInput "model" "MODEL" 21)
          (mkInput "clip" "CLIP" 22)
          (mkInput "vae" "VAE" 23)
          (mkInput "positive" "CONDITIONING" 24)
          (mkInput "negative" "CONDITIONING" 25)
          (mkInput "bbox_detector" "BBOX_DETECTOR" 26)
        ];
        outputs = [
          (mkOutput "image" "IMAGE" [ 27 ])
          (mkOutput "cropped_refined" "IMAGE" [ ])
          (mkOutput "cropped_enhanced_alpha" "IMAGE" [ ])
          (mkOutput "mask" "MASK" [ ])
          (mkOutput "detailer_pipe" "DETAILER_PIPE" [ ])
          (mkOutput "cnet_images" "IMAGE" [ ])
        ];
        widgets = [
          512 # guide_size
          true # guide_size_for(bbox)
          1024 # max_size
        ]
        ++ seedWidgets
        ++ [
          18 # steps
          4 # cfg
          "euler" # sampler_name
          "simple" # scheduler
          0.35 # denoise
          5 # feather
          true # noise_mask
          true # force_inpaint
          0.5 # bbox_threshold
          10 # bbox_dilation
          3.0 # bbox_crop_factor
          "center-1" # sam_detection_hint
          0 # sam_dilation
          0.93 # sam_threshold
          0 # sam_bbox_expansion
          0.7 # sam_mask_hint_threshold
          "False" # sam_mask_hint_use_negative
          32 # drop_size
          "" # wildcard
          1 # cycle
          false # inpaint_model
          20 # noise_mask_feather
          false # tiled_encode
          false # tiled_decode
        ];
      })
      (mkNode {
        id = 18;
        type = "SaveImage";
        pos = [
          3040
          180
        ];
        size = [
          420
          470
        ];
        order = 19;
        inputs = [ (mkInput "images" "IMAGE" 27) ];
        widgets = [ (mkFilenamePrefix name) ];
      })
    ];
    links = [
      [
        30
        20
        0
        6
        0
        "INT"
      ]
      [
        31
        20
        1
        6
        1
        "INT"
      ]
      [
        10
        1
        0
        10
        0
        "MODEL"
      ]
      [
        1
        10
        0
        7
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
        4
        0
        7
        1
        "CONDITIONING"
      ]
      [
        5
        5
        0
        7
        2
        "CONDITIONING"
      ]
      [
        6
        6
        0
        7
        3
        "LATENT"
      ]
      [
        7
        7
        0
        8
        0
        "LATENT"
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
        9
        0
        11
        0
        "UPSCALE_MODEL"
      ]
      [
        11
        8
        0
        11
        1
        "IMAGE"
      ]
      [
        12
        11
        0
        12
        0
        "IMAGE"
      ]
      [
        29
        12
        0
        19
        0
        "IMAGE"
      ]
      [
        13
        19
        0
        13
        0
        "IMAGE"
      ]
      [
        28
        3
        0
        13
        1
        "VAE"
      ]
      [
        14
        10
        0
        14
        0
        "MODEL"
      ]
      [
        15
        4
        0
        14
        1
        "CONDITIONING"
      ]
      [
        16
        5
        0
        14
        2
        "CONDITIONING"
      ]
      [
        17
        13
        0
        14
        3
        "LATENT"
      ]
      [
        18
        14
        0
        15
        0
        "LATENT"
      ]
      [
        19
        3
        0
        15
        1
        "VAE"
      ]
      [
        20
        15
        0
        17
        0
        "IMAGE"
      ]
      [
        21
        10
        0
        17
        1
        "MODEL"
      ]
      [
        22
        2
        0
        17
        2
        "CLIP"
      ]
      [
        23
        3
        0
        17
        3
        "VAE"
      ]
      [
        24
        4
        0
        17
        4
        "CONDITIONING"
      ]
      [
        25
        5
        0
        17
        5
        "CONDITIONING"
      ]
      [
        26
        16
        0
        17
        6
        "BBOX_DETECTOR"
      ]
      [
        27
        17
        0
        18
        0
        "IMAGE"
      ]
    ];
  };
}
