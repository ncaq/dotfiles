# hires fix(アップスケールモデル+2パス目のKSampler)と、
# FaceDetailerによる顔の修復を加えた標準構成のパイプライン。
# 解像度と保存名を変えたワークフローを作るための共有部品で、
# ワークフローとして直接は配置されない。
#
# hires fixは2倍アップスケール後に0.75倍へ縮小するので、
# 最終出力は生成解像度の1.5倍になる。
#
# FaceDetailerの`widgets_values`の並びは、
# ComfyUI-Impact-Pack 8.28の定義に合わせている。
#
# `promptNodes`が使うノード1から5と16、
# リンク1から8と28/29は避けて番号を振る必要がある。
# ここはノード15とリンク27まで使っていて、
# 次の空き番号が`promptNodes`のLoraLoaderに当たるため、
# ノードやリンクを足す時は16と28/29を飛ばして17と30から振る。
{
  lib,
  width,
  height,
  # ワークフロー名。出力先サブディレクトリとファイル名の元になる。
  name,
}:
let
  inherit (import ./builder.nix { inherit lib; })
    mkNode
    mkInput
    mkOutput
    mkAppInput
    mkAppInputWith
    mkWorkflow
    mkFilenamePrefix
    promptNodes
    promptLinks
    seedWidgets
    samplerName
    schedulerName
    baseSteps
    stepsForDenoise
    ;
  hiresDenoise = 0.45;
  faceDenoise = 0.5;
in
mkWorkflow {
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
      (mkAppInput 5 "seed")
    ];
    outputs = [ 15 ];
  };
  nodes =
    promptNodes {
      inherit width height;
      # KSampler2とFaceDetailerへ。
      extraModelLinks = [
        14
        21
      ];
      # FaceDetailerへ。
      extraClipLinks = [ 22 ];
      # VAEEncode、VAEDecode2、FaceDetailerへ。
      extraVaeLinks = [
        13
        19
        23
      ];
      # KSampler2とFaceDetailerへ。
      extraPositiveLinks = [
        15
        24
      ];
      extraNegativeLinks = [
        16
        25
      ];
    }
    ++ [
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
        order = 8;
        inputs = [
          (mkInput "samples" "LATENT" 7)
          (mkInput "vae" "VAE" 8)
        ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 10 ]) ];
      })
      (mkNode {
        id = 7;
        type = "UpscaleModelLoader";
        pos = [
          1290
          60
        ];
        size = [
          315
          58
        ];
        order = 6;
        outputs = [ (mkOutput "UPSCALE_MODEL" "UPSCALE_MODEL" [ 9 ]) ];
        widgets = [ "2x-AnimeSharpV4_Fast_RCAN_PU.safetensors" ];
      })
      (mkNode {
        id = 8;
        type = "ImageUpscaleWithModel";
        pos = [
          1560
          200
        ];
        size = [
          240
          46
        ];
        order = 9;
        inputs = [
          (mkInput "upscale_model" "UPSCALE_MODEL" 9)
          (mkInput "image" "IMAGE" 10)
        ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 11 ]) ];
      })
      # 2倍アップスケール後に0.75倍へ縮小して、
      # 全体で1.5倍のhires fixにする。
      # 縮小を挟むのはスーパーサンプリングになってエッジが整うため。
      (mkNode {
        id = 9;
        type = "ImageScaleBy";
        pos = [
          1560
          300
        ];
        size = [
          315
          82
        ];
        order = 10;
        inputs = [ (mkInput "image" "IMAGE" 11) ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 12 ]) ];
        widgets = [
          "area" # upscale_method
          0.75 # scale_by
        ];
      })
      (mkNode {
        id = 10;
        type = "VAEEncode";
        pos = [
          1560
          440
        ];
        size = [
          210
          46
        ];
        order = 11;
        inputs = [
          (mkInput "pixels" "IMAGE" 12)
          (mkInput "vae" "VAE" 13)
        ];
        outputs = [ (mkOutput "LATENT" "LATENT" [ 17 ]) ];
      })
      # 2パス目。低めのdenoiseで書き込みを増やす。
      # stepsは`stepsForDenoise`で素の生成と刻み密度を揃える。
      (mkNode {
        id = 11;
        type = "KSampler";
        pos = [
          1940
          200
        ];
        size = [
          315
          262
        ];
        order = 12;
        inputs = [
          (mkInput "model" "MODEL" 14)
          (mkInput "positive" "CONDITIONING" 15)
          (mkInput "negative" "CONDITIONING" 16)
          (mkInput "latent_image" "LATENT" 17)
        ];
        outputs = [ (mkOutput "LATENT" "LATENT" [ 18 ]) ];
        widgets = seedWidgets ++ [
          (stepsForDenoise baseSteps hiresDenoise) # steps
          5.5 # cfg
          samplerName
          schedulerName
          hiresDenoise
        ];
      })
      (mkNode {
        id = 12;
        type = "VAEDecode";
        pos = [
          2310
          200
        ];
        size = [
          210
          46
        ];
        order = 13;
        inputs = [
          (mkInput "samples" "LATENT" 18)
          (mkInput "vae" "VAE" 19)
        ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 20 ]) ];
      })
      (mkNode {
        id = 13;
        type = "UltralyticsDetectorProvider";
        pos = [
          2310
          60
        ];
        size = [
          315
          78
        ];
        order = 7;
        outputs = [
          (mkOutput "BBOX_DETECTOR" "BBOX_DETECTOR" [ 26 ])
          (mkOutput "SEGM_DETECTOR" "SEGM_DETECTOR" [ ])
        ];
        widgets = [ "bbox/face_yolov9c.pt" ];
      })
      (mkNode {
        id = 14;
        type = "FaceDetailer";
        pos = [
          2580
          200
        ];
        size = [
          400
          800
        ];
        order = 14;
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
          (stepsForDenoise baseSteps faceDenoise) # steps
          5.5 # cfg
          samplerName
          schedulerName
          faceDenoise
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
          10 # drop_size
          "" # wildcard
          1 # cycle
          false # inpaint_model
          20 # noise_mask_feather
          false # tiled_encode
          false # tiled_decode
        ];
      })
      (mkNode {
        id = 15;
        type = "SaveImage";
        pos = [
          3040
          200
        ];
        size = [
          420
          470
        ];
        order = 15;
        inputs = [ (mkInput "images" "IMAGE" 27) ];
        widgets = [ (mkFilenamePrefix name) ];
      })
    ];
  links = promptLinks ++ [
    [
      9
      7
      0
      8
      0
      "UPSCALE_MODEL"
    ]
    [
      10
      6
      0
      8
      1
      "IMAGE"
    ]
    [
      11
      8
      0
      9
      0
      "IMAGE"
    ]
    [
      12
      9
      0
      10
      0
      "IMAGE"
    ]
    [
      13
      1
      2
      10
      1
      "VAE"
    ]
    [
      14
      16
      0
      11
      0
      "MODEL"
    ]
    [
      15
      2
      0
      11
      1
      "CONDITIONING"
    ]
    [
      16
      3
      0
      11
      2
      "CONDITIONING"
    ]
    [
      17
      10
      0
      11
      3
      "LATENT"
    ]
    [
      18
      11
      0
      12
      0
      "LATENT"
    ]
    [
      19
      1
      2
      12
      1
      "VAE"
    ]
    [
      20
      12
      0
      14
      0
      "IMAGE"
    ]
    [
      21
      16
      0
      14
      1
      "MODEL"
    ]
    [
      22
      16
      1
      14
      2
      "CLIP"
    ]
    [
      23
      1
      2
      14
      3
      "VAE"
    ]
    [
      24
      2
      0
      14
      4
      "CONDITIONING"
    ]
    [
      25
      3
      0
      14
      5
      "CONDITIONING"
    ]
    [
      26
      13
      0
      14
      6
      "BBOX_DETECTOR"
    ]
    [
      27
      14
      0
      15
      0
      "IMAGE"
    ]
  ];
}
