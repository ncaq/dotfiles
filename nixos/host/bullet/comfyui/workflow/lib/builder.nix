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

  # 出力をワークフローごとのサブディレクトリへ分けて、
  # ファイル名を連番だけでなく生成日時にするfilename_prefixを組み立てる。
  # %year%などの置換はサーバ側のfolder_paths.get_save_image_pathが行うため、
  # フロントエンドの%date:...%と違い自作ノードを含む全ての保存ノードで機能する。
  # 第1引数はワークフロー名で、サブディレクトリ名とファイル名の両方に使われる。
  # 第2引数はファイル名だけに足すサフィックスで、
  # 同じワークフローが複数の保存ノードを持つ時に役割を区別する。
  # サブディレクトリはワークフロー単位のままなので階層は増えない。
  mkFilenamePrefixWith =
    name: suffix: "${name}/${name}${suffix}-%year%-%month%-%day%-%hour%-%minute%-%second%";
  mkFilenamePrefix = name: mkFilenamePrefixWith name "";

  mkNode =
    {
      id,
      type,
      pos,
      size,
      # ノードの実行順。
      # ノードごとに一意で、かつリンクの依存に沿って増える値を振る。
      # `lib/order.nix`の検証がこの規約を機械的に確かめる。
      order,
      inputs ? [ ],
      outputs ? [ ],
      widgets ? null,
      # ノードの表示名。役割が分かる名前を付ける時に指定する。
      # 未指定ならComfyUIがノード型のデフォルト表示名を使う。
      title ? null,
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
    // lib.optionalAttrs (widgets != null) { widgets_values = widgets; }
    // lib.optionalAttrs (title != null) { inherit title; };
  mkInput = name: type: link: { inherit name type link; };
  mkOutput = name: type: links: { inherit name type links; };
  mkAppInput = nodeId: widgetName: [
    nodeId
    widgetName
  ];
  mkAppInputWith = nodeId: widgetName: config: [
    nodeId
    widgetName
    config
  ];
  # LoRA Managerの`Lora Loader (LoraManager)`ノード。
  # LoRAが未指定ならMODELとCLIPをそのまま素通しするので、
  # 常に配線したままで良い。
  # LoRA Managerの管理画面のSend to Workflowがこのノードへ流し込む。
  #
  # 入力スロットの並びとウィジェットの並びはノード定義に一致させる必要があり、
  # 崩れるとSend to Workflowが動かなくなる。
  # UIで開くまで気付けないため、ここに一箇所だけ定義して`lib/builder-test.nix`で検証する。
  # ウィジェットは順に、LoRA一覧を保持する内部状態、テキスト、有効なLoRAのリスト。
  #
  # CLIPとlora_stackは`shape = 7`のオプション入力になっている。
  # UNETにだけ作用するLoRAを扱うワークフローでは、
  # `clipLink`を省略してCLIPを繋がずに使う。
  mkLoraLoader =
    {
      id,
      pos,
      order,
      title ? null,
      # MODEL入力へ繋ぐリンクID。
      modelLink,
      # CLIP入力へ繋ぐリンクID。nullならCLIPは未接続にする。
      clipLink ? null,
      # MODEL出力から出るリンクIDのリスト。
      modelLinks,
      # CLIP出力から出るリンクIDのリスト。
      clipLinks ? [ ],
    }:
    mkNode {
      inherit
        id
        pos
        order
        title
        ;
      type = "Lora Loader (LoraManager)";
      # フロントエンドがLoRA一覧の領域を確保するため最低でもこの程度の高さで描画される。
      size = [
        385
        350
      ];
      inputs = [
        (mkInput "model" "MODEL" modelLink)
        {
          name = "text";
          type = "AUTOCOMPLETE_TEXT_LORAS";
          widget = {
            name = "text";
          };
          link = null;
        }
        ((mkInput "clip" "CLIP" clipLink) // { shape = 7; })
        {
          name = "lora_stack";
          type = "LORA_STACK";
          shape = 7;
          link = null;
        }
      ];
      outputs = [
        (mkOutput "MODEL" "MODEL" modelLinks)
        (mkOutput "CLIP" "CLIP" clipLinks)
        (mkOutput "trigger_words" "STRING" [ ])
        (mkOutput "loaded_loras" "STRING" [ ])
      ];
      widgets = [
        {
          version = 1;
          textWidgetName = "text";
        }
        ""
        [ ]
      ];
    };
  mkWorkflow =
    {
      nodes,
      links,
      app ? null,
    }:
    {
      inherit nodes links;
      last_node_id = lib.foldl' lib.max 0 (map (node: node.id) nodes);
      last_link_id = lib.foldl' lib.max 0 (map lib.head links);
      groups = [ ];
      config = { };
      extra = lib.optionalAttrs (app != null) {
        # App Mode向けの入力定義は保持しつつ、通常はNode Graphで開く。
        linearMode = false;
        linearData = app;
      };
      version = 0.4;
    };

  # checkpoint読み込み、LoRA適用、プロンプトエンコードの共通部分。
  # どのワークフローも同じノードIDとリンクIDで始まる。
  # リンク: 28=MODEL→LoraLoader, 29=CLIP→LoraLoader,
  # 1=MODEL→KSampler, 2/3=CLIP→TextEncode,
  # 4/5=CONDITIONING→KSampler, 6=LATENT→KSampler
  # 後段の構成によっては同じ出力を追加のノードにも繋ぐので、
  # 追加のリンクIDを引数で受け取る。
  # MODELとCLIPの追加リンクはLoRA適用後のLoraLoader(ノード16)から出る。
  #
  # LoraLoaderのノードID 16とリンクID 28/29は、
  # 呼び出し元が使うIDと衝突しない大きめの値を予約している。
  #
  # img2imgのようにEmptyLatentImage以外からLATENTを供給する場合は、
  # `withEmptyLatent = false`にして、
  # 呼び出し元が代替ノードからリンク6をKSamplerへ張る。
  promptNodes =
    {
      width ? defaultWidth,
      height ? defaultHeight,
      # falseにするとEmptyLatentImage(ノード4)を生成しない。
      withEmptyLatent ? true,
      # img2imgでは1未満にして元画像の構図を残す。
      denoise ? 1,
      # withEmptyLatent = falseで代替ノードを複数挟む場合に、
      # KSamplerのorderを後ろへずらすための値。
      samplerOrder ? 5,
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
          20
        ];
        size = [
          385
          98
        ];
        order = 0;
        outputs = [
          (mkOutput "MODEL" "MODEL" [ 28 ])
          (mkOutput "CLIP" "CLIP" [ 29 ])
          (mkOutput "VAE" "VAE" ([ 8 ] ++ extraVaeLinks))
        ];
        widgets = [ checkpoint ];
      })
      # オプショナルなLoRA適用。
      (mkLoraLoader {
        id = 16;
        pos = [
          (-40)
          200
        ];
        order = 1;
        modelLink = 28;
        clipLink = 29;
        modelLinks = [ 1 ] ++ extraModelLinks;
        clipLinks = [
          2
          3
        ]
        ++ extraClipLinks;
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
        order = 2;
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
        order = 3;
        inputs = [ (mkInput "clip" "CLIP" 3) ];
        outputs = [ (mkOutput "CONDITIONING" "CONDITIONING" ([ 5 ] ++ extraNegativeLinks)) ];
        widgets = [ negativePrompt ];
      })
    ]
    ++ lib.optional withEmptyLatent (mkNode {
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
      order = 4;
      outputs = [ (mkOutput "LATENT" "LATENT" [ 6 ]) ];
      widgets = [
        width
        height
        1 # batch_size
      ];
    })
    ++ [
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
        order = samplerOrder;
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
          denoise
        ];
      })
    ];
  # EmptyLatentImage由来のリンク6を含まない共通リンク。
  # `withEmptyLatent = false`のワークフローはこちらを使って、
  # 代替のLATENT源からリンク6を自前で張る。
  promptBaseLinks = [
    [
      28
      1
      0
      16
      0
      "MODEL"
    ]
    [
      29
      1
      1
      16
      2
      "CLIP"
    ]
    [
      1
      16
      0
      5
      0
      "MODEL"
    ]
    [
      2
      16
      1
      2
      0
      "CLIP"
    ]
    [
      3
      16
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
  promptLinks = promptBaseLinks ++ [
    [
      6
      4
      0
      5
      3
      "LATENT"
    ]
  ];
in
{
  inherit
    mkNode
    mkInput
    mkOutput
    mkLoraLoader
    mkAppInput
    mkAppInputWith
    mkWorkflow
    mkFilenamePrefix
    mkFilenamePrefixWith
    promptNodes
    promptBaseLinks
    promptLinks
    seedWidgets
    samplerName
    schedulerName
    ;
}
