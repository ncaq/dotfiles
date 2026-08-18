# Qwen-Image-Edit 2511による指示ベースの画像編集。
# 「Remove the object on the table」のような自然言語の指示文で、
# 読み込んだ画像を編集する。
# 通常のimg2img(anima-editやsdxl-edit)と違い、
# 元画像の同一性を保ったまま指示箇所だけを変更できる。
#
# 公式テンプレートのimage_qwen_image_edit_2511.jsonから、
# Lightning LoRAの切り替えスイッチ類を除いた基本構成。
# サンプリング設定はQwen公式推奨値(40 steps, CFG 4.0)。
#
# 指示文は公式には英語と中国語がサポート対象なので、
# 自作カスタムノードのTranslate Text to Englishを前段に置いて、
# 日本語で書いた指示を英語へ翻訳してから渡す。
# 言語は自動判定なので英語原文を直接書いてもそのまま通る。
# 翻訳に失敗した場合は原文がそのまま渡される。
#
# TextEncodeQwenImageEditPlusは参照画像を3枚まで受け取れる。
# 1枚目が編集対象で、2枚目以降は任意の参照になる。
# 生成解像度は1枚目から決まるので、
# 2枚目以降を足しても出力サイズは変わらない。
{ lib, ... }:
let
  name = "qwen-edit";
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
        (mkAppInput 4 "image")
        (mkAppInputWith 17 "image" {
          description = "任意。編集箇所の拡大や赤枠を描いた画像を渡すと対象を特定しやすい";
        })
        (mkAppInputWith 18 "image" {
          description = "任意。さらに参照させたい画像";
        })
        (mkAppInputWith 14 "text" {
          height = 160;
          description = "画像への編集指示。日本語でも英語でも入力可能";
        })
        (mkAppInput 11 "seed")
      ];
      outputs = [ 13 ];
    };
    nodes = [
      (mkNode {
        id = 1;
        type = "UNETLoader";
        pos = [
          (-40)
          60
        ];
        size = [
          385
          82
        ];
        order = 0;
        outputs = [ (mkOutput "MODEL" "MODEL" [ 21 ]) ];
        widgets = [
          "qwen_image_edit_2511_int8_convrot.safetensors"
          "default" # weight_dtype
        ];
      })
      # オプショナルなLoRA適用。
      # Qwen系のLoRAはUNETにだけ作用するのでCLIPは繋がない。
      (mkLoraLoader {
        id = 16;
        pos = [
          (-40)
          200
        ];
        order = 1;
        modelLink = 21;
        modelLinks = [ 1 ];
      })
      (mkNode {
        id = 2;
        type = "CLIPLoader";
        pos = [
          (-40)
          700
        ];
        size = [
          385
          106
        ];
        order = 2;
        outputs = [
          (mkOutput "CLIP" "CLIP" [
            2
            3
          ])
        ];
        widgets = [
          "qwen_2.5_vl_7b.safetensors"
          "qwen_image" # type
          "default" # device
        ];
      })
      (mkNode {
        id = 3;
        type = "VAELoader";
        pos = [
          (-40)
          860
        ];
        size = [
          385
          58
        ];
        order = 3;
        outputs = [
          (mkOutput "VAE" "VAE" [
            4
            5
            6
            7
          ])
        ];
        widgets = [ "qwen_image_vae.safetensors" ];
      })
      (mkNode {
        id = 4;
        type = "LoadImage";
        title = "編集する画像";
        pos = [
          (-40)
          980
        ];
        size = [
          340
          314
        ];
        order = 4;
        outputs = [
          (mkOutput "IMAGE" "IMAGE" [ 8 ])
          (mkOutput "MASK" "MASK" [ ])
        ];
        widgets = [
          "example.png"
          "image"
        ];
      })
      # 編集する画像に加えて渡せる参照画像。
      # 自作のLoadImageOptionalで、(none)のままなら未指定扱いになる。
      #
      # TextEncodeQwenImageEditPlusは参照画像をQwen2.5-VLへ渡す前に、
      # 総画素384*384(長辺400px程度)まで縮小する。
      # 指示文の対象を決めているのはこのVLなので、
      # 画像全体を1枚渡すだけでは小さい対象がそもそも見えていない。
      # 編集したい箇所を切り出した画像や、
      # 対象を赤枠で囲んだ画像を追加で渡すと、
      # その分だけVLから見た実効解像度が上がって対象を特定しやすくなる。
      # 指示文では公式の例と同じく「image 2」のように番号で参照する。
      #
      # このノードはリサイズを挟まず直結する。
      # エンコード側がVL用に384*384、参照latent用に1024*1024へ内部で縮小するため、
      # 前段のリサイズは効果がなく、
      # FluxKontextImageScaleは生成解像度を決める画像1にだけ必要になる。
      (mkNode {
        id = 17;
        type = "LoadImageOptional";
        title = "参照画像2(任意)";
        pos = [
          (-40)
          1340
        ];
        size = [
          340
          314
        ];
        order = 5;
        outputs = [
          (mkOutput "IMAGE" "IMAGE" [
            22
            23
          ])
          (mkOutput "MASK" "MASK" [ ])
        ];
        widgets = [
          "(none)"
          "image"
        ];
      })
      (mkNode {
        id = 18;
        type = "LoadImageOptional";
        title = "参照画像3(任意)";
        pos = [
          (-40)
          1700
        ];
        size = [
          340
          314
        ];
        order = 6;
        outputs = [
          (mkOutput "IMAGE" "IMAGE" [
            24
            25
          ])
          (mkOutput "MASK" "MASK" [ ])
        ];
        widgets = [
          "(none)"
          "image"
        ];
      })
      # 入力画像をモデルに適した解像度へリサイズする。
      (mkNode {
        id = 5;
        type = "FluxKontextImageScale";
        pos = [
          420
          620
        ];
        size = [
          240
          46
        ];
        order = 7;
        inputs = [ (mkInput "image" "IMAGE" 8) ];
        outputs = [
          (mkOutput "IMAGE" "IMAGE" [
            9
            10
            11
          ])
        ];
      })
      # 編集指示をここに書く。
      # 日本語で書けば英語へ翻訳され、英語で書けばほぼそのまま通る。
      (mkNode {
        id = 14;
        type = "TranslateTextToEnglish";
        title = "編集指示(日本語でも英語でも可)";
        pos = [
          420
          (-200)
        ];
        size = [
          420
          200
        ];
        order = 8;
        outputs = [
          (mkOutput "english_text" "STRING" [
            19
            20
          ])
        ];
        widgets = [ "背景を星空に変えてください。" ];
      })
      # 実行時に翻訳後の英文を表示する。
      # 意図と違う訳になっていないか確認する用。
      (mkNode {
        id = 15;
        type = "PreviewAny";
        title = "翻訳後の英文";
        pos = [
          880
          (-200)
        ];
        size = [
          340
          200
        ];
        order = 9;
        inputs = [ (mkInput "source" "*" 20) ];
      })
      # 編集指示。画像を参照しながら指示文をエンコードする。
      # 指示文は翻訳ノードから入力ソケット経由で受け取るので、
      # promptウィジェットはソケットに変換した状態で置く。
      (mkNode {
        id = 6;
        type = "TextEncodeQwenImageEditPlus";
        title = "編集指示のエンコード";
        pos = [
          420
          60
        ];
        size = [
          420
          240
        ];
        order = 10;
        inputs = [
          (mkInput "clip" "CLIP" 2)
          (mkInput "vae" "VAE" 4)
          (mkInput "image1" "IMAGE" 9)
          (mkInput "image2" "IMAGE" 22)
          (mkInput "image3" "IMAGE" 24)
          (
            mkInput "prompt" "STRING" 19
            // {
              widget = {
                name = "prompt";
              };
            }
          )
        ];
        outputs = [ (mkOutput "CONDITIONING" "CONDITIONING" [ 12 ]) ];
        widgets = [ "" ];
      })
      # ネガティブ側は空の指示文。
      (mkNode {
        id = 7;
        type = "TextEncodeQwenImageEditPlus";
        title = "ネガティブ(空のまま)";
        pos = [
          420
          360
        ];
        size = [
          420
          200
        ];
        order = 11;
        inputs = [
          (mkInput "clip" "CLIP" 3)
          (mkInput "vae" "VAE" 5)
          (mkInput "image1" "IMAGE" 10)
          (mkInput "image2" "IMAGE" 23)
          (mkInput "image3" "IMAGE" 25)
        ];
        outputs = [ (mkOutput "CONDITIONING" "CONDITIONING" [ 13 ]) ];
        widgets = [ "" ];
      })
      (mkNode {
        id = 8;
        type = "ModelSamplingAuraFlow";
        pos = [
          920
          60
        ];
        size = [
          315
          58
        ];
        order = 12;
        inputs = [ (mkInput "model" "MODEL" 1) ];
        outputs = [ (mkOutput "MODEL" "MODEL" [ 14 ]) ];
        widgets = [ 3.1 ]; # shift
      })
      (mkNode {
        id = 9;
        type = "CFGNorm";
        pos = [
          920
          180
        ];
        size = [
          315
          82
        ];
        order = 13;
        inputs = [ (mkInput "model" "MODEL" 14) ];
        outputs = [ (mkOutput "patched_model" "MODEL" [ 15 ]) ];
        widgets = [
          1 # strength
          false # pre_cfg
        ];
      })
      (mkNode {
        id = 10;
        type = "VAEEncode";
        pos = [
          420
          720
        ];
        size = [
          210
          46
        ];
        order = 14;
        inputs = [
          (mkInput "pixels" "IMAGE" 11)
          (mkInput "vae" "VAE" 6)
        ];
        outputs = [ (mkOutput "LATENT" "LATENT" [ 16 ]) ];
      })
      (mkNode {
        id = 11;
        type = "KSampler";
        pos = [
          920
          320
        ];
        size = [
          315
          262
        ];
        order = 15;
        inputs = [
          (mkInput "model" "MODEL" 15)
          (mkInput "positive" "CONDITIONING" 12)
          (mkInput "negative" "CONDITIONING" 13)
          (mkInput "latent_image" "LATENT" 16)
        ];
        outputs = [ (mkOutput "LATENT" "LATENT" [ 17 ]) ];
        widgets = seedWidgets ++ [
          40 # steps
          4 # cfg
          "euler"
          "simple"
          1 # denoise
        ];
      })
      (mkNode {
        id = 12;
        type = "VAEDecode";
        pos = [
          1290
          320
        ];
        size = [
          210
          46
        ];
        order = 16;
        inputs = [
          (mkInput "samples" "LATENT" 17)
          (mkInput "vae" "VAE" 7)
        ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 18 ]) ];
      })
      (mkNode {
        id = 13;
        type = "SaveImage";
        pos = [
          1560
          320
        ];
        size = [
          420
          470
        ];
        order = 17;
        inputs = [ (mkInput "images" "IMAGE" 18) ];
        widgets = [ (mkFilenamePrefix name) ];
      })
    ];
    links = [
      [
        21
        1
        0
        16
        0
        "MODEL"
      ]
      [
        1
        16
        0
        8
        0
        "MODEL"
      ]
      [
        2
        2
        0
        6
        0
        "CLIP"
      ]
      [
        3
        2
        0
        7
        0
        "CLIP"
      ]
      [
        4
        3
        0
        6
        1
        "VAE"
      ]
      [
        5
        3
        0
        7
        1
        "VAE"
      ]
      [
        6
        3
        0
        10
        1
        "VAE"
      ]
      [
        7
        3
        0
        12
        1
        "VAE"
      ]
      [
        8
        4
        0
        5
        0
        "IMAGE"
      ]
      [
        9
        5
        0
        6
        2
        "IMAGE"
      ]
      [
        10
        5
        0
        7
        2
        "IMAGE"
      ]
      [
        11
        5
        0
        10
        0
        "IMAGE"
      ]
      [
        12
        6
        0
        11
        1
        "CONDITIONING"
      ]
      [
        13
        7
        0
        11
        2
        "CONDITIONING"
      ]
      [
        14
        8
        0
        9
        0
        "MODEL"
      ]
      [
        15
        9
        0
        11
        0
        "MODEL"
      ]
      [
        16
        10
        0
        11
        3
        "LATENT"
      ]
      [
        17
        11
        0
        12
        0
        "LATENT"
      ]
      [
        18
        12
        0
        13
        0
        "IMAGE"
      ]
      [
        19
        14
        0
        6
        5
        "STRING"
      ]
      [
        20
        14
        0
        15
        0
        "STRING"
      ]
      [
        22
        17
        0
        6
        3
        "IMAGE"
      ]
      [
        23
        17
        0
        7
        3
        "IMAGE"
      ]
      [
        24
        18
        0
        6
        4
        "IMAGE"
      ]
      [
        25
        18
        0
        7
        4
        "IMAGE"
      ]
    ];
  };
}
