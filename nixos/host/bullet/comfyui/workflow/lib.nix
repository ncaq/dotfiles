# ComfyUIのワークフローJSON(UI形式)をNix式で組み立てるための共有部品。
#
# UI形式のノードの`widgets_values`は配列で、
# 並び順はノード定義のINPUT_TYPESのウィジェット順に一致させる必要がある。
{ lib }:
let
  checkpoint = "waiIllustriousSDXL_v170.safetensors";
  positivePrompt = "best quality, amazing quality, masterpiece, 1girl";
  negativePrompt = "bad quality, worst quality, worst detail, sketch, censored, watermark, signature";
  # Illustrious系モデルの定番サンプリング設定。
  samplerName = "euler_ancestral";
  schedulerName = "normal";
  # SDXLのポートレートバケット解像度をデフォルトにする。
  defaultWidth = 832;
  defaultHeight = 1216;
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
  # どのワークフローも同じノードIDとリンクIDで始まる。
  # リンク: 1=MODEL→KSampler, 2/3=CLIP→TextEncode,
  # 4/5=CONDITIONING→KSampler, 6=LATENT→KSampler
  # 後段の構成によっては同じ出力を追加のノードにも繋ぐので、
  # 追加のリンクIDを引数で受け取る。
  promptNodes =
    {
      width ? defaultWidth,
      height ? defaultHeight,
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
          1 # batch_size
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
          28 # steps
          5.5 # cfg
          samplerName
          schedulerName
          1 # denoise
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
in
{
  inherit
    mkNode
    mkInput
    mkOutput
    mkWorkflow
    promptNodes
    promptLinks
    seedWidgets
    samplerName
    schedulerName
    ;
}
