# ComfyUIのワークフローJSON(UI形式)をNix式から生成して、
# ComfyUIのuserディレクトリへシンボリックリンクで配置する。
#
# UI形式のノードの`widgets_values`は配列で、
# 並び順はノード定義のINPUT_TYPESのウィジェット順に一致させる必要がある。
# FaceDetailerの並びはComfyUI-Impact-Pack 8.28の定義に合わせている。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  dataDir = config.containers.comfyui.config.services.comfyui.dataDir;
  jsonFormat = pkgs.formats.json { };
  checkpoint = "waiIllustriousSDXL_v170.safetensors";
  positivePrompt = "best quality, amazing quality, masterpiece, 1girl";
  negativePrompt = "bad quality, worst quality, worst detail, sketch, censored, watermark, signature";
  # Illustrious系モデルの定番サンプリング設定。
  samplerName = "euler_ancestral";
  schedulerName = "normal";
  # SDXLのポートレートバケット解像度。
  width = 832;
  height = 1216;
  # seedウィジェットは値の直後に実行後の挙動(randomizeなど)が並ぶ。
  seedWidgets = [
    0
    "randomize"
  ];

  mkNode =
    {
      id,
      type,
      pos,
      size,
      order,
      inputs ? [ ],
      outputs ? [ ],
      widgets ? null,
    }:
    {
      inherit
        id
        type
        pos
        size
        order
        inputs
        outputs
        ;
      flags = { };
      mode = 0;
      properties = {
        "Node name for S&R" = type;
      };
    }
    // lib.optionalAttrs (widgets != null) { widgets_values = widgets; };
  mkInput = name: type: link: { inherit name type link; };
  mkOutput = name: type: links: { inherit name type links; };
  mkWorkflow =
    { nodes, links }:
    {
      inherit nodes links;
      last_node_id = lib.foldl' lib.max 0 (map (node: node.id) nodes);
      last_link_id = lib.foldl' lib.max 0 (map lib.head links);
      groups = [ ];
      config = { };
      extra = { };
      version = 0.4;
    };

  # checkpoint読み込みとプロンプトエンコードの共通部分。
  # 基本形もフル構成も同じノードIDとリンクIDで始まる。
  # リンク: 1=MODEL→KSampler, 2/3=CLIP→TextEncode,
  # 4/5=CONDITIONING→KSampler, 6=LATENT→KSampler
  # フル構成では同じ出力を後段ノードにも繋ぐので、
  # 追加のリンクIDを引数で受け取る。
  promptNodes =
    {
      extraModelLinks ? [ ],
      extraClipLinks ? [ ],
      extraVaeLinks ? [ ],
      extraPositiveLinks ? [ ],
      extraNegativeLinks ? [ ],
    }:
    [
      (mkNode {
        id = 1;
        type = "CheckpointLoaderSimple";
        pos = [
          (-40)
          200
        ];
        size = [
          385
          98
        ];
        order = 0;
        outputs = [
          (mkOutput "MODEL" "MODEL" ([ 1 ] ++ extraModelLinks))
          (mkOutput "CLIP" "CLIP" (
            [
              2
              3
            ]
            ++ extraClipLinks
          ))
          (mkOutput "VAE" "VAE" ([ 8 ] ++ extraVaeLinks))
        ];
        widgets = [ checkpoint ];
      })
      (mkNode {
        id = 2;
        type = "CLIPTextEncode";
        pos = [
          420
          60
        ];
        size = [
          420
          160
        ];
        order = 1;
        inputs = [ (mkInput "clip" "CLIP" 2) ];
        outputs = [ (mkOutput "CONDITIONING" "CONDITIONING" ([ 4 ] ++ extraPositiveLinks)) ];
        widgets = [ positivePrompt ];
      })
      (mkNode {
        id = 3;
        type = "CLIPTextEncode";
        pos = [
          420
          280
        ];
        size = [
          420
          160
        ];
        order = 2;
        inputs = [ (mkInput "clip" "CLIP" 3) ];
        outputs = [ (mkOutput "CONDITIONING" "CONDITIONING" ([ 5 ] ++ extraNegativeLinks)) ];
        widgets = [ negativePrompt ];
      })
      (mkNode {
        id = 4;
        type = "EmptyLatentImage";
        pos = [
          420
          500
        ];
        size = [
          315
          106
        ];
        order = 3;
        outputs = [ (mkOutput "LATENT" "LATENT" [ 6 ]) ];
        widgets = [
          width
          height
          1
        ];
      })
      (mkNode {
        id = 5;
        type = "KSampler";
        pos = [
          920
          200
        ];
        size = [
          315
          262
        ];
        order = 4;
        inputs = [
          (mkInput "model" "MODEL" 1)
          (mkInput "positive" "CONDITIONING" 4)
          (mkInput "negative" "CONDITIONING" 5)
          (mkInput "latent_image" "LATENT" 6)
        ];
        outputs = [ (mkOutput "LATENT" "LATENT" [ 7 ]) ];
        widgets = seedWidgets ++ [
          28
          5.5
          samplerName
          schedulerName
          1
        ];
      })
    ];
  promptLinks = [
    [
      1
      1
      0
      5
      0
      "MODEL"
    ]
    [
      2
      1
      1
      2
      0
      "CLIP"
    ]
    [
      3
      1
      1
      3
      0
      "CLIP"
    ]
    [
      4
      2
      0
      5
      1
      "CONDITIONING"
    ]
    [
      5
      3
      0
      5
      2
      "CONDITIONING"
    ]
    [
      6
      4
      0
      5
      3
      "LATENT"
    ]
    [
      7
      5
      0
      6
      0
      "LATENT"
    ]
    [
      8
      1
      2
      6
      1
      "VAE"
    ]
  ];
  # 属性名がワークフロー名(ファイル名)になり、
  # 値はそのままJSONへ変換できるNixの値。
  workflows = {
    # txt2imgの基本形。
    anime-basic = mkWorkflow {
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

    # hires fix(アップスケールモデル+2パス目のKSampler)と、
    # FaceDetailerによる顔の修復を加えたフル構成。
    anime-hires-face = mkWorkflow {
      nodes =
        promptNodes {
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
            order = 7;
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
            order = 5;
            outputs = [ (mkOutput "UPSCALE_MODEL" "UPSCALE_MODEL" [ 9 ]) ];
            widgets = [ "4x-AnimeSharp.safetensors" ];
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
            order = 8;
            inputs = [
              (mkInput "upscale_model" "UPSCALE_MODEL" 9)
              (mkInput "image" "IMAGE" 10)
            ];
            outputs = [ (mkOutput "IMAGE" "IMAGE" [ 11 ]) ];
          })
          # 4倍アップスケール後に0.375倍へ縮小して、
          # 全体で1.5倍のhires fixにする。
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
            order = 9;
            inputs = [ (mkInput "image" "IMAGE" 11) ];
            outputs = [ (mkOutput "IMAGE" "IMAGE" [ 12 ]) ];
            widgets = [
              "lanczos"
              0.375
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
            order = 10;
            inputs = [
              (mkInput "pixels" "IMAGE" 12)
              (mkInput "vae" "VAE" 13)
            ];
            outputs = [ (mkOutput "LATENT" "LATENT" [ 17 ]) ];
          })
          # 2パス目。低めのdenoiseで書き込みを増やす。
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
            order = 11;
            inputs = [
              (mkInput "model" "MODEL" 14)
              (mkInput "positive" "CONDITIONING" 15)
              (mkInput "negative" "CONDITIONING" 16)
              (mkInput "latent_image" "LATENT" 17)
            ];
            outputs = [ (mkOutput "LATENT" "LATENT" [ 18 ]) ];
            widgets = seedWidgets ++ [
              20
              5.5
              samplerName
              schedulerName
              0.45
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
            order = 12;
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
            order = 6;
            outputs = [
              (mkOutput "BBOX_DETECTOR" "BBOX_DETECTOR" [ 26 ])
              (mkOutput "SEGM_DETECTOR" "SEGM_DETECTOR" [ ])
            ];
            widgets = [ "bbox/face_yolov8m.pt" ];
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
            order = 13;
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
            # 並び: guide_size, guide_size_for, max_size, seed(+挙動),
            # steps, cfg, sampler_name, scheduler, denoise, feather,
            # noise_mask, force_inpaint, bbox系, sam系, drop_size,
            # wildcard, cycle, optionalのinpaint_model,
            # noise_mask_feather, tiled_encode, tiled_decode
            widgets = [
              512
              true
              1024
            ]
            ++ seedWidgets
            ++ [
              20
              5.5
              samplerName
              schedulerName
              0.5
              5
              true
              true
              0.5
              10
              3.0
              "center-1"
              0
              0.93
              0
              0.7
              "False"
              10
              ""
              1
              false
              20
              false
              false
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
            order = 14;
            inputs = [ (mkInput "images" "IMAGE" 27) ];
            widgets = [ "anime-hires-face" ];
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
          1
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
          1
          0
          14
          1
          "MODEL"
        ]
        [
          22
          1
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
    };
  };
in
{
  # シンボリックリンク先はUIから上書き保存できないので、
  # 編集したものを残したい場合は別名で保存する。
  systemd.tmpfiles.rules = [
    "d ${dataDir}/user 0755 comfyui comfyui - -"
    "d ${dataDir}/user/default 0755 comfyui comfyui - -"
    "d ${dataDir}/user/default/workflows 0755 comfyui comfyui - -"
  ]
  ++ lib.mapAttrsToList (
    name: workflow:
    "L+ ${dataDir}/user/default/workflows/${name}.json - - - - ${jsonFormat.generate "${name}.json" workflow}"
  ) workflows;
}
