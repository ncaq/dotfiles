# Qwen-Image-2.1による指示ベースの画像編集。
# 「Remove the object on the table」のような自然言語の指示文で、
# 読み込んだ画像を編集する。
# 通常のimg2img(anima-editやsdxl-edit)と違い、
# 元画像の同一性を保ったまま指示箇所だけを変更できる。
#
# 公式テンプレートのimage_qwen_image_2_1_image_edit.jsonから、
# サブグラフや切り替えスイッチ類を除いた基本構成。
# 2.1は生成と編集を1つのモデルで行い、
# 参照画像を渡すかどうかで編集になる。
#
# サンプリングは公式パイプラインの推奨範囲の下限の40 steps、CFG 1。
# 公式テンプレートは25 stepsから始めているが、
# CFG 1ならステップごとにDiTを1回しか回さないので、
# CFG 4で2回ずつ回していた2511の40 stepsより軽い。
# shiftもモデル側の既定値のままで、
# 公式テンプレートと同じくModelSamplingAuraFlowもCFGNormも挟まない。
#
# 指示文は公式には英語と中国語がサポート対象なので、
# 自作カスタムノードのRewrite Edit Promptを前段に置いて、
# 日本語で書いた指示を英文の編集命令へ書き換えてから渡す。
# 書き換えるのはQwen-Image-2.1公式の編集指示リライト用モデルPE-I2Iで、
# 対象と属性と位置を明示し、変えない部分まで書き下した英文になる。
# 編集する画像も一緒に渡すので、
# 「この子の服装を変えて」のような曖昧な指示でも対象を特定できる。
# 書き換えに失敗した場合はGoogle翻訳へ、それも駄目なら原文へ倒れる。
#
# TextEncodeQwenImage21は参照画像を16枚まで受け取れるが、
# ここでは3枚までにする。
# 参照が3枚を超えると人物同士で髪型や小物が混ざるという報告があり、
# 枠を増やしても画面が込み入るだけで使い道が無い。
# 1枚目が編集対象で、2枚目以降は任意の参照になる。
# 出力の比率は指示に応じてPE-I2Iが決め、普通の編集なら1枚目の比率になる。
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
    qwenImageEditResolution
    ;
  # TextEncodeQwenImage21の参照画像の入力。
  # 数が増えていく入力(Autogrow)なので、
  # API形式でも`images.image_1`のようにグループ名で修飾した名前で渡る。
  mkReferenceInput =
    index: link:
    mkInput "images.image_${toString index}" "IMAGE" link
    // {
      # 任意の入力であることを表す形。
      # フロントエンドが保存するワークフローと同じにしておく。
      shape = 7;
    };
in
{
  local.comfyui.workflows.${name} = mkWorkflow {
    app = {
      inputs = [
        (mkAppInput 4 "image")
        (mkAppInputWith 17 "image" {
          description = "任意。指示文から「画像2」のように番号で参照できる";
        })
        (mkAppInputWith 18 "image" {
          description = "任意。指示文から「画像3」のように番号で参照できる";
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
      # 指示文のリライトに使うPE-I2I。
      # 公式版は指示によって拒否するので、拒否の方向を取り除いたheretic版を使う。
      # 理由は`model.nix`に書いてある。
      # テキストエンコーダではなく文章生成に使うが、読み込みはCLIPLoaderで行う。
      # ComfyUIは重みの中身からQwen3.5 9Bと判定するのでtypeは何でもよく、
      # 他のQwen-Image-2.1のファイルと揃えておく。
      (mkNode {
        id = 19;
        type = "CLIPLoader";
        title = "指示文リライトモデル(PE-I2I)";
        pos = [
          (-40)
          (-200)
        ];
        size = [
          385
          106
        ];
        order = 0;
        outputs = [ (mkOutput "CLIP" "CLIP" [ 12 ]) ];
        widgets = [
          "qwen3.5_9b_qwen_image_2.1_pe_i2i_heretic.int8_convrot.safetensors"
          "qwen_image" # type
          "default" # device
        ];
      })
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
        order = 1;
        outputs = [ (mkOutput "MODEL" "MODEL" [ 1 ]) ];
        widgets = [
          "qwen_image_2.1_int8_convrot.safetensors"
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
        order = 2;
        modelLink = 1;
        modelLinks = [ 2 ];
      })
      # ComfyUIは重みの中身からQwen3-VL 8Bと判定し、
      # typeが`qwen_image`ならQwen-Image-2.1用のテキストエンコーダとして読む。
      # 同じtypeでも2511までのQwen2.5-VLなら旧来のものになる。
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
        order = 3;
        outputs = [ (mkOutput "CLIP" "CLIP" [ 3 ]) ];
        widgets = [
          "qwen3vl_8b_bf16.safetensors"
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
        order = 4;
        outputs = [
          (mkOutput "VAE" "VAE" [
            4
            5
          ])
        ];
        widgets = [ "qwen_image_2.1_vae_bf16.safetensors" ];
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
        order = 5;
        outputs = [
          (mkOutput "IMAGE" "IMAGE" [
            6
            7
          ])
          (mkOutput "MASK" "MASK" [ ])
        ];
        widgets = [
          "example.png"
          "image"
        ];
      })
      # 編集する画像に加えて渡せる参照画像。
      # 自作のLoadImageOptionalで、(none)のままなら未指定扱いになる。
      # 未指定の枠は詰めて数えられるので、
      # 3枚目だけを指定するとそれが指示文での「画像2」になる。
      #
      # 2511ではテキストエンコーダへ渡す画像が総画素384*384まで縮められていたため、
      # 対象を切り出した画像を足してVLから見た解像度を補う使い方をしていた。
      # 2.1ではテキストエンコーダもVAEと同じ解像度の画像を見るので、
      # その目的では要らなくなり、純粋に別の画像を参照させるための枠になった。
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
        order = 6;
        outputs = [
          (mkOutput "IMAGE" "IMAGE" [
            8
            9
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
        order = 7;
        outputs = [
          (mkOutput "IMAGE" "IMAGE" [
            10
            11
          ])
          (mkOutput "MASK" "MASK" [ ])
        ];
        widgets = [
          "(none)"
          "image"
        ];
      })
      # 編集指示をここに書く。
      # 日本語で書けば英文の編集命令へ書き換えられ、英語で書いても整えられる。
      #
      # 書き換えのseedは生成のseedと分けて固定しておく。
      # 公式どおりtemperature 1.0でサンプリングするので、
      # seedを変えるたびに書き換えも揺れてやり直しになる。
      # 固定しておけば、生成のseedだけ変える連打ではこのノードはキャッシュが効く。
      #
      # PE-I2Iは指示文と一緒に出力のキャンバスの形も決める。
      # 普通の編集なら1枚目の比率のままだが、
      # 「画像2の構図で」なら2枚目の比率を、
      # 新しい構図を作る指示なら16:9のような比率を選ぶ。
      # その寸法を幅と高さとして出すので、空のlatentはそれで作る。
      (mkNode {
        id = 14;
        type = "RewriteEditPrompt";
        title = "編集指示(日本語でも英語でも可)";
        pos = [
          420
          (-260)
        ];
        size = [
          420
          260
        ];
        order = 8;
        inputs = [
          (mkInput "clip" "CLIP" 12)
          (mkInput "image1" "IMAGE" 7)
          (mkInput "image2" "IMAGE" 9)
          (mkInput "image3" "IMAGE" 11)
        ];
        outputs = [
          (mkOutput "english_text" "STRING" [
            13
            14
          ])
          (mkOutput "width" "INT" [ 20 ])
          (mkOutput "height" "INT" [ 21 ])
        ];
        widgets = [
          "背景を星空に変えてください。"
          0 # seed
          "fixed" # control_after_generate
          qwenImageEditResolution
        ];
      })
      # 実行時に書き換え後の英文を表示する。
      # 意図と違う指示になっていないか確認する用。
      (mkNode {
        id = 15;
        type = "PreviewAny";
        title = "書き換え後の英文";
        pos = [
          880
          (-200)
        ];
        size = [
          340
          200
        ];
        order = 9;
        inputs = [ (mkInput "source" "*" 14) ];
      })
      # 編集指示と参照画像をエンコードする。
      # 指示文は書き換えノードから入力ソケット経由で受け取るので、
      # promptウィジェットはソケットに変換した状態で置く。
      #
      # このノードは1枚目の寸法に合わせた空のlatentも出すが使わない。
      # 出力の寸法は書き換えノードが決める。
      # 1枚目に従う場合は同じ式で同じ寸法になるので、普通の編集では結果は変わらない。
      (mkNode {
        id = 6;
        type = "TextEncodeQwenImage21";
        title = "編集指示のエンコード";
        pos = [
          420
          60
        ];
        size = [
          420
          360
        ];
        order = 10;
        inputs = [
          (mkInput "clip" "CLIP" 3)
          (mkInput "vae" "VAE" 4)
          (
            mkInput "prompt" "STRING" 13
            // {
              widget = {
                name = "prompt";
              };
            }
          )
          (mkReferenceInput 1 6)
          (mkReferenceInput 2 8)
          (mkReferenceInput 3 10)
          # 数が増えていく入力は、繋がった最後の枠の次に空の枠を1つ置く。
          # フロントエンドが保存する形と揃えておく。
          (mkReferenceInput 4 null)
        ];
        outputs = [
          (mkOutput "positive" "CONDITIONING" [ 15 ])
          (mkOutput "negative" "CONDITIONING" [ 16 ])
          (mkOutput "latent" "LATENT" [ ])
        ];
        widgets = [
          "" # prompt
          "" # negative_prompt
          qwenImageEditResolution
        ];
      })
      # 書き換えノードが決めた寸法の空のlatent。
      # EmptyLatentImageは4チャンネルで8倍縮小のlatentを作るが、
      # 中身が空ならサンプラーがモデルのlatent形式である64チャンネルで16倍縮小へ直す。
      # 公式のテキストからの生成テンプレートも同じ作りになっている。
      (mkNode {
        id = 20;
        type = "EmptyLatentImage";
        pos = [
          920
          400
        ];
        size = [
          315
          106
        ];
        order = 11;
        inputs = [
          (
            mkInput "width" "INT" 20
            // {
              widget = {
                name = "width";
              };
            }
          )
          (
            mkInput "height" "INT" 21
            // {
              widget = {
                name = "height";
              };
            }
          )
        ];
        outputs = [ (mkOutput "LATENT" "LATENT" [ 17 ]) ];
        widgets = [
          qwenImageEditResolution # width
          qwenImageEditResolution # height
          1 # batch_size
        ];
      })
      (mkNode {
        id = 11;
        type = "KSampler";
        pos = [
          920
          60
        ];
        size = [
          315
          262
        ];
        order = 12;
        inputs = [
          (mkInput "model" "MODEL" 2)
          (mkInput "positive" "CONDITIONING" 15)
          (mkInput "negative" "CONDITIONING" 16)
          (mkInput "latent_image" "LATENT" 17)
        ];
        outputs = [ (mkOutput "LATENT" "LATENT" [ 18 ]) ];
        widgets = seedWidgets ++ [
          40 # steps
          1 # cfg
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
          60
        ];
        size = [
          210
          46
        ];
        order = 13;
        inputs = [
          (mkInput "samples" "LATENT" 18)
          (mkInput "vae" "VAE" 5)
        ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 19 ]) ];
      })
      (mkNode {
        id = 13;
        type = "SaveImage";
        pos = [
          1560
          60
        ];
        size = [
          420
          470
        ];
        order = 14;
        inputs = [ (mkInput "images" "IMAGE" 19) ];
        widgets = [ (mkFilenamePrefix name) ];
      })
    ];
    links = [
      [
        1
        1
        0
        16
        0
        "MODEL"
      ]
      [
        2
        16
        0
        11
        0
        "MODEL"
      ]
      [
        3
        2
        0
        6
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
        12
        1
        "VAE"
      ]
      [
        6
        4
        0
        6
        3
        "IMAGE"
      ]
      [
        7
        4
        0
        14
        1
        "IMAGE"
      ]
      [
        8
        17
        0
        6
        4
        "IMAGE"
      ]
      [
        9
        17
        0
        14
        2
        "IMAGE"
      ]
      [
        10
        18
        0
        6
        5
        "IMAGE"
      ]
      [
        11
        18
        0
        14
        3
        "IMAGE"
      ]
      [
        12
        19
        0
        14
        0
        "CLIP"
      ]
      [
        13
        14
        0
        6
        2
        "STRING"
      ]
      [
        14
        14
        0
        15
        0
        "STRING"
      ]
      [
        15
        6
        0
        11
        1
        "CONDITIONING"
      ]
      [
        16
        6
        1
        11
        2
        "CONDITIONING"
      ]
      [
        17
        20
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
        12
        0
        13
        0
        "IMAGE"
      ]
      [
        20
        14
        1
        20
        0
        "INT"
      ]
      [
        21
        14
        2
        20
        1
        "INT"
      ]
    ];
  };
}
