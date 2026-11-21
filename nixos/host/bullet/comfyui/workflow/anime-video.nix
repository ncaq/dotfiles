# アニメ調イラスト1枚をMiniMax H3で音付きの動画にするワークフロー。
#
# 公式テンプレートvideo_minimax_h3_i2vと同じ構成を、
# サブグラフや切り替えスイッチを除いてフラットに展開したもの。
# lightx2vの8ステップ蒸留LoRAを常に効かせて、8ステップで生成する。
# CFGは使わないのでネガティブプロンプトは無い。
#
# 蒸留LoRAは768p(1344x768)で、動画のshiftを6、音声のshiftを3にして学習されている。
# 本体の既定のshiftは12と3なので、MiniMaxH3SigmaShiftでLoRAの学習時の値へ合わせる。
# 生成解像度も入力画像から768p相当へ自動で決める。
# アスペクト比を保ったまま1344x768と同じ総ピクセル量へスケールして、
# 32の倍数へ丸めた実寸をMiniMaxH3ImageToVideoへ渡す。
#
# ポジティブプロンプトの先頭にはアニメスタイル指定を固定で結合する。
# 指定が無くても入力画像の絵柄はおおむね保たれるが、
# 実写や3Dへ寄るのを避けるために入れてある。
#
# 動画の長さは秒数で指定する。
# MiniMax H3は24fpsで、フレーム数は17k+5の形しか取れない。
# 学習されているのは124フレーム(約5秒)から362フレーム(約15秒)なので、
# その範囲で指定する。
# コアのMath Expressionノードが秒数から17k+5のフレーム数を計算して、
# MiniMaxH3ImageToVideoのlengthへソケットで渡す。
#
# 任意で動画の終了ポーズも画像で指定できる。
# 成り行き生成では動作が中途半端なポーズで終わりやすく、
# anime-video-extendでの継ぎ足しの破綻に繋がる。
# 「終了ポーズの画像」ノードで画像を選ぶと、
# MiniMaxH3ImageToVideoが末尾フレームを指定画像へ固定するため、
# 動作が動画内で必ず完結する。
# 終了ポーズの画像は開始画像を元にsdxl-editやqwen-editなどで先に作っておく。
# ノード内部で生成解像度へ中央クロップされるため、
# 開始画像と同じアスペクト比の画像を用意するのが安全。
# (none)のままなら自作のLoadImageOptionalがNoneを出力して、
# last_frameは未指定扱いになり、
# 開始フレームのみの成り行き生成になる。
#
# 動きの指示は日本語で書けば自作カスタムノードで英語へ翻訳される。
# カメラワーク(近づく、回り込むなど)と動作を具体的に書くと動きが出やすい。
# 音も同じ指示文から作られるので、鳴らしたい音や鳴らしたくない音も書ける。
# 出力は自作保存ノードによるSVT-AV1 losslessの映像とOpusの音声のWebM。
# 8-bit RGBから10-bit YUV 4:2:0への色変換後の映像を可逆圧縮する。
# 色変換とクロマサブサンプリングを挟むため、元のRGB画像に対する厳密な可逆圧縮ではない。
{ lib, ... }:
let
  name = "anime-video";
  inherit (import ./lib/builder.nix { inherit lib; })
    mkNode
    mkInput
    mkWidgetInput
    mkOutput
    mkLoraLoader
    mkAppInput
    mkAppInputWith
    mkWorkflow
    mkFilenamePrefix
    seedWidgets
    ;
  # 実写や3Dへ寄るのを避けるために常にプロンプトへ前置するスタイル指定。
  animeStylePrefix = "Anime style, 2D cel animation, flat colors.";
  # autogrowの次の空きスロット。shape 7はoptionalの意味。
  mathSpareInput = mkInput "values.b" "FLOAT,INT,BOOLEAN" null // {
    shape = 7;
  };
in
{
  local.comfyui.workflows.${name} = mkWorkflow {
    app = {
      inputs = [
        (mkAppInput 9 "image")
        (mkAppInputWith 30 "image" {
          description = "任意。動画の最後に到達させたいポーズ";
        })
        (mkAppInputWith 19 "text" {
          height = 160;
          description = "動きとカメラワークと音。日本語でも英語でも入力可能";
        })
        (mkAppInputWith 25 "value" {
          description = "動画の長さの秒数。5から15まで";
        })
        (mkAppInput 13 "noise_seed")
      ];
      outputs = [ 17 ];
    };
    nodes = [
      (mkNode {
        id = 1;
        type = "UNETLoader";
        title = "MiniMax H3モデル";
        pos = [
          1340
          40
        ];
        size = [
          385
          82
        ];
        order = 0;
        outputs = [ (mkOutput "MODEL" "MODEL" [ 1 ]) ];
        widgets = [
          "minimax_h3_fl2va_pruned_int8_convrot.safetensors"
          "default" # weight_dtype
        ];
      })
      # 8ステップで生成できるようにする蒸留LoRA。常に効かせる。
      (mkNode {
        id = 34;
        type = "LoraLoaderModelOnly";
        title = "8ステップ蒸留LoRA";
        pos = [
          1340
          190
        ];
        size = [
          385
          82
        ];
        order = 1;
        inputs = [ (mkInput "model" "MODEL" 1) ];
        outputs = [ (mkOutput "MODEL" "MODEL" [ 2 ]) ];
        widgets = [
          "minimax_h3_fl2v_turbo_8step_v1.2_768p_comfyui_bf16.safetensors"
          1 # strength_model
        ];
      })
      # オプショナルなLoRA適用。
      # MiniMax H3のLoRAは拡散モデルにだけ作用するのでCLIPは繋がない。
      (mkLoraLoader {
        id = 31;
        title = "LoRA";
        pos = [
          1340
          340
        ];
        order = 2;
        modelLink = 2;
        modelLinks = [ 3 ];
      })
      # 蒸留LoRAの学習時のshiftへ合わせる。
      (mkNode {
        id = 7;
        type = "MiniMaxH3SigmaShift";
        title = "shift";
        pos = [
          1340
          870
        ];
        size = [
          315
          82
        ];
        order = 3;
        inputs = [ (mkInput "model" "MODEL" 3) ];
        outputs = [
          (mkOutput "MODEL" "MODEL" [
            4
            5
          ])
        ];
        widgets = [
          6 # shift_video
          3 # shift_audio
        ];
      })
      (mkNode {
        id = 3;
        type = "CLIPLoader";
        pos = [
          880
          40
        ];
        size = [
          385
          106
        ];
        order = 4;
        outputs = [ (mkOutput "CLIP" "CLIP" [ 6 ]) ];
        widgets = [
          "qwen3vl_32b_minimax_h3_int8_convrot.safetensors"
          "minimax" # type
          "default" # device
        ];
      })
      (mkNode {
        id = 4;
        type = "VAELoader";
        title = "映像のVAE";
        pos = [
          880
          220
        ];
        size = [
          385
          58
        ];
        order = 5;
        outputs = [
          (mkOutput "VAE" "VAE" [
            7
            8
          ])
        ];
        widgets = [ "minimax_h3_video_vae_fp16.safetensors" ];
      })
      (mkNode {
        id = 33;
        type = "VAELoader";
        title = "音声のVAE";
        pos = [
          880
          350
        ];
        size = [
          385
          58
        ];
        order = 6;
        outputs = [ (mkOutput "VAE" "VAE" [ 9 ]) ];
        widgets = [ "minimax_h3_audio_vae_fp32.safetensors" ];
      })
      (mkNode {
        id = 9;
        type = "LoadImage";
        title = "動かす画像";
        pos = [
          (-40)
          320
        ];
        size = [
          340
          314
        ];
        order = 7;
        outputs = [
          (mkOutput "IMAGE" "IMAGE" [ 10 ])
          (mkOutput "MASK" "MASK" [ ])
        ];
        widgets = [
          "example.png"
          "image"
        ];
      })
      # 動画の最後に到達させたいポーズの画像。任意。
      # (none)のままならNoneを出力して終了フレームは未指定になる。
      (mkNode {
        id = 30;
        type = "LoadImageOptional";
        title = "終了ポーズの画像(任意)";
        pos = [
          (-40)
          710
        ];
        size = [
          340
          314
        ];
        order = 8;
        outputs = [
          (mkOutput "IMAGE" "IMAGE" [ 11 ])
          (mkOutput "MASK" "MASK" [ ])
        ];
        widgets = [
          "(none)"
          "image"
        ];
      })
      # アスペクト比を保って768p相当の総ピクセル量へスケールしつつ、
      # 幅と高さをMiniMax H3の要求する32の倍数へ丸める。
      # 0.98は16:9の画像がちょうど蒸留LoRAの学習解像度の1344x768になる値。
      # 生成を速くしたい時はmegapixelsを0.5などへ下げる。
      (mkNode {
        id = 21;
        type = "ImageScaleToTotalPixels";
        title = "生成解像度へスケール";
        pos = [
          480
          520
        ];
        size = [
          315
          130
        ];
        order = 9;
        inputs = [ (mkInput "image" "IMAGE" 10) ];
        outputs = [
          (mkOutput "IMAGE" "IMAGE" [
            12
            13
          ])
        ];
        widgets = [
          "lanczos" # upscale_method
          0.98 # megapixels
          32 # resolution_steps
        ];
      })
      # スケール後の実寸をMiniMaxH3ImageToVideoへ渡す。
      (mkNode {
        id = 22;
        type = "GetImageSize";
        pos = [
          480
          730
        ];
        size = [
          240
          86
        ];
        order = 10;
        inputs = [ (mkInput "image" "IMAGE" 13) ];
        outputs = [
          (mkOutput "width" "INT" [ 14 ])
          (mkOutput "height" "INT" [ 15 ])
          (mkOutput "batch_size" "INT" [ ])
        ];
      })
      # 動画の長さを秒数で指定する。
      (mkNode {
        id = 25;
        type = "PrimitiveFloat";
        title = "動画の長さ(秒): 5から15まで";
        pos = [
          (-40)
          1110
        ];
        size = [
          460
          82
        ];
        order = 11;
        outputs = [ (mkOutput "FLOAT" "FLOAT" [ 16 ]) ];
        widgets = [ 5 ]; # value
      })
      # MiniMaxH3ImageToVideoのlengthへ渡すフレーム数を秒数aから計算する。
      # 24fpsでのフレーム数を、17k+5の形になるように切り上げる。
      # 公式テンプレートの式と同じ。
      # 5秒なら120が124になる。
      (mkNode {
        id = 24;
        type = "ComfyMathExpression";
        title = "フレーム数を計算";
        pos = [
          480
          1110
        ];
        size = [
          315
          106
        ];
        order = 12;
        inputs = [
          (mkInput "values.a" "FLOAT,INT,BOOLEAN" 16)
          mathSpareInput
        ];
        outputs = [
          (mkOutput "FLOAT" "FLOAT" [ ])
          (mkOutput "INT" "INT" [
            17
            18
          ])
          (mkOutput "BOOL" "BOOLEAN" [ ])
        ];
        widgets = [ "max(5, round(a * 24)) + (5 - (max(5, round(a * 24)) % 17)) % 17" ];
      })
      # フレーム数を24fpsの秒数へ換算する。実行時の表示用。
      (mkNode {
        id = 28;
        type = "ComfyMathExpression";
        title = "フレーム数を秒数へ換算";
        pos = [
          480
          1280
        ];
        size = [
          315
          106
        ];
        order = 13;
        inputs = [
          (mkInput "values.a" "FLOAT,INT,BOOLEAN" 18)
          mathSpareInput
        ];
        outputs = [
          (mkOutput "FLOAT" "FLOAT" [ 19 ])
          (mkOutput "INT" "INT" [ ])
          (mkOutput "BOOL" "BOOLEAN" [ ])
        ];
        widgets = [ "round(a / 24 * 10) / 10" ];
      })
      # 実行時に実際の秒数を表示する。
      # ノードのタイトルやウィジェットを入力に応じてリアルタイムに書き換えるには、
      # フロントエンドのJavaScript拡張が必要なため実行時表示で妥協している。
      (mkNode {
        id = 29;
        type = "PreviewAny";
        title = "実際の動画の長さ(秒)";
        pos = [
          840
          1280
        ];
        size = [
          240
          106
        ];
        order = 14;
        inputs = [ (mkInput "source" "*" 19) ];
      })
      # 動きの指示をここに書く。
      # 日本語で書けば英語へ翻訳され、英語で書けばほぼそのまま通る。
      (mkNode {
        id = 19;
        type = "TranslateTextToEnglish";
        title = "動きの指示(日本語でも英語でも可)";
        pos = [
          (-40)
          40
        ];
        size = [
          420
          200
        ];
        order = 15;
        outputs = [ (mkOutput "english_text" "STRING" [ 20 ]) ];
        widgets = [
          "カメラはゆっくりと近づく。キャラクターは穏やかに微笑み、髪と服が風に揺れる。"
          # 翻訳モデルへ伝える用途。動画生成の動きの指示。
          "video"
        ];
      })
      # アニメスタイル指定を動きの指示の前に固定で結合する。
      (mkNode {
        id = 18;
        type = "StringConcatenate";
        title = "アニメスタイル指定の前置";
        pos = [
          480
          40
        ];
        size = [
          340
          130
        ];
        order = 16;
        inputs = [ (mkWidgetInput "string_b" "STRING" 20) ];
        outputs = [
          (mkOutput "STRING" "STRING" [
            21
            22
          ])
        ];
        widgets = [
          animeStylePrefix
          ""
          " " # delimiter
        ];
      })
      # 実行時に最終的な英語プロンプトを表示する。
      # 意図と違う訳になっていないか確認する用。
      (mkNode {
        id = 20;
        type = "PreviewAny";
        title = "最終プロンプト";
        pos = [
          480
          240
        ];
        size = [
          340
          200
        ];
        order = 17;
        inputs = [ (mkInput "source" "*" 22) ];
      })
      # 指示文と開始フレームから条件付けと空のlatentを作る。
      # latentは映像と音声を1つにまとめたもので、
      # サンプリングの後でそれぞれのVAEが自分の分だけを取り出して復元する。
      # last_frameは任意入力で、終了ポーズ画像が指定されている時だけ、
      # 末尾フレームが指定画像へ固定される。
      # 解像度とフレーム数はソケット経由で自動で入るので手動調整は不要。
      (mkNode {
        id = 12;
        type = "MiniMaxH3ImageToVideo";
        pos = [
          880
          520
        ];
        size = [
          400
          300
        ];
        order = 18;
        inputs = [
          (mkInput "clip" "CLIP" 6)
          (mkInput "vae" "VAE" 7)
          (mkInput "first_frame" "IMAGE" 12 // { shape = 7; })
          (mkInput "last_frame" "IMAGE" 11 // { shape = 7; })
          (mkWidgetInput "prompt" "STRING" 21)
          (mkWidgetInput "width" "INT" 14)
          (mkWidgetInput "height" "INT" 15)
          (mkWidgetInput "length" "INT" 17)
        ];
        outputs = [
          (mkOutput "positive" "CONDITIONING" [ 23 ])
          (mkOutput "LATENT" "LATENT" [ 24 ])
        ];
        widgets = [
          "" # prompt(ソケットから上書きされる)
          1344 # width(ソケットから上書きされる)
          768 # height(ソケットから上書きされる)
          124 # length(フレーム数計算ノードから上書きされる)
        ];
      })
      (mkNode {
        id = 13;
        type = "RandomNoise";
        pos = [
          1800
          40
        ];
        size = [
          315
          82
        ];
        order = 19;
        outputs = [ (mkOutput "NOISE" "NOISE" [ 25 ]) ];
        widgets = seedWidgets;
      })
      (mkNode {
        id = 35;
        type = "KSamplerSelect";
        pos = [
          1800
          190
        ];
        size = [
          315
          58
        ];
        order = 20;
        outputs = [ (mkOutput "SAMPLER" "SAMPLER" [ 26 ]) ];
        widgets = [ "res_multistep" ];
      })
      # ステップ数は蒸留LoRAの推奨の8。
      (mkNode {
        id = 36;
        type = "BasicScheduler";
        pos = [
          1800
          320
        ];
        size = [
          315
          106
        ];
        order = 21;
        inputs = [ (mkInput "model" "MODEL" 4) ];
        outputs = [ (mkOutput "SIGMAS" "SIGMAS" [ 27 ]) ];
        widgets = [
          "simple" # scheduler
          8 # steps
          1 # denoise
        ];
      })
      (mkNode {
        id = 37;
        type = "BasicGuider";
        pos = [
          1800
          500
        ];
        size = [
          240
          46
        ];
        order = 22;
        inputs = [
          (mkInput "model" "MODEL" 5)
          (mkInput "conditioning" "CONDITIONING" 23)
        ];
        outputs = [ (mkOutput "GUIDER" "GUIDER" [ 28 ]) ];
      })
      (mkNode {
        id = 14;
        type = "SamplerCustomAdvanced";
        pos = [
          1800
          620
        ];
        size = [
          355
          106
        ];
        order = 23;
        inputs = [
          (mkInput "noise" "NOISE" 25)
          (mkInput "guider" "GUIDER" 28)
          (mkInput "sampler" "SAMPLER" 26)
          (mkInput "sigmas" "SIGMAS" 27)
          (mkInput "latent_image" "LATENT" 24)
        ];
        outputs = [
          (mkOutput "output" "LATENT" [
            29
            30
          ])
          (mkOutput "denoised_output" "LATENT" [ ])
        ];
      })
      (mkNode {
        id = 15;
        type = "VAEDecode";
        pos = [
          2220
          40
        ];
        size = [
          210
          46
        ];
        order = 24;
        inputs = [
          (mkInput "samples" "LATENT" 29)
          (mkInput "vae" "VAE" 8)
        ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 31 ]) ];
      })
      (mkNode {
        id = 38;
        type = "VAEDecodeAudio";
        pos = [
          2220
          160
        ];
        size = [
          210
          46
        ];
        order = 25;
        inputs = [
          (mkInput "samples" "LATENT" 30)
          (mkInput "vae" "VAE" 9)
        ];
        outputs = [ (mkOutput "AUDIO" "AUDIO" [ 32 ]) ];
      })
      # MiniMax H3は24fpsで学習されているのでfpsは24のまま使う。
      (mkNode {
        id = 17;
        type = "SaveSvtAv1";
        pos = [
          2220
          280
        ];
        size = [
          420
          470
        ];
        order = 26;
        inputs = [
          (mkInput "images" "IMAGE" 31)
          (mkInput "audio" "AUDIO" 32 // { shape = 7; })
        ];
        widgets = [
          (mkFilenamePrefix name) # filename_prefix
          24 # fps
          4 # preset
        ];
      })
    ];
    links = [
      [
        1
        1
        0
        34
        0
        "MODEL"
      ]
      [
        2
        34
        0
        31
        0
        "MODEL"
      ]
      [
        3
        31
        0
        7
        0
        "MODEL"
      ]
      [
        4
        7
        0
        36
        0
        "MODEL"
      ]
      [
        5
        7
        0
        37
        0
        "MODEL"
      ]
      [
        6
        3
        0
        12
        0
        "CLIP"
      ]
      [
        7
        4
        0
        12
        1
        "VAE"
      ]
      [
        8
        4
        0
        15
        1
        "VAE"
      ]
      [
        9
        33
        0
        38
        1
        "VAE"
      ]
      [
        10
        9
        0
        21
        0
        "IMAGE"
      ]
      [
        11
        30
        0
        12
        3
        "IMAGE"
      ]
      [
        12
        21
        0
        12
        2
        "IMAGE"
      ]
      [
        13
        21
        0
        22
        0
        "IMAGE"
      ]
      [
        14
        22
        0
        12
        5
        "INT"
      ]
      [
        15
        22
        1
        12
        6
        "INT"
      ]
      [
        16
        25
        0
        24
        0
        "FLOAT"
      ]
      [
        17
        24
        1
        12
        7
        "INT"
      ]
      [
        18
        24
        1
        28
        0
        "INT"
      ]
      [
        19
        28
        0
        29
        0
        "FLOAT"
      ]
      [
        20
        19
        0
        18
        0
        "STRING"
      ]
      [
        21
        18
        0
        12
        4
        "STRING"
      ]
      [
        22
        18
        0
        20
        0
        "STRING"
      ]
      [
        23
        12
        0
        37
        1
        "CONDITIONING"
      ]
      [
        24
        12
        1
        14
        4
        "LATENT"
      ]
      [
        25
        13
        0
        14
        0
        "NOISE"
      ]
      [
        26
        35
        0
        14
        2
        "SAMPLER"
      ]
      [
        27
        36
        0
        14
        3
        "SIGMAS"
      ]
      [
        28
        37
        0
        14
        1
        "GUIDER"
      ]
      [
        29
        14
        0
        15
        0
        "LATENT"
      ]
      [
        30
        14
        0
        38
        0
        "LATENT"
      ]
      [
        31
        15
        0
        17
        0
        "IMAGE"
      ]
      [
        32
        38
        0
        17
        1
        "AUDIO"
      ]
    ];
  };
}
