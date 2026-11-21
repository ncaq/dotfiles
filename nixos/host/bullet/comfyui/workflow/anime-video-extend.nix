# anime-videoで生成した動画を約5秒(124フレーム)延長するワークフロー。
#
# anime-videoが一度に作れるのは学習範囲の15秒までで、
# それより長い動画や、途中で指示を変えたい動画は1回では作れない。
# こちらは既存動画の最終フレームを開始画像にして続きを生成し、
# 元動画と連結して出力する継ぎ足し方式。
# 各区間の絵は直前の区間の最終ポーズに固定されるため動作が前へ進み、
# 区間ごとに動きの指示を変えて演出できる。
# 結果を確認しながら好きな回数繰り返して延長できる。
#
# 弱点は繋ぎ目で動きの勢いと音が一瞬途切れることと、
# 区間を重ねるごとに色味や質感が少しずつ劣化していくこと。
#
# 入力はanime-videoかこのワークフローが作った、音付きで24fpsの動画を前提にする。
# 音声の無い動画を入れると、元動画の音声と新区間の音声を連結する所で失敗する。
#
# 任意で区間の終了ポーズも画像で指定できる。
# 成り行き生成では5秒以内に動作が完結せず中途半端なポーズで終わって、
# 次の継ぎ足しが破綻しやすい。
# 「終了ポーズの画像」ノードで画像を選ぶと、
# MiniMaxH3ImageToVideoが末尾フレームを指定画像へ固定するため、
# 動作が区間内で必ず完結し、
# キーフレームを先に用意しておけば長尺の動きを計画的に設計できる。
# 終了ポーズの画像は元動画の最終フレームを元に、
# sdxl-editやqwen-editなどで先に作っておく。
# ノード内部で生成解像度へ中央クロップされるため、
# 元動画と同じアスペクト比の画像を用意するのが安全。
# (none)のままなら自作のLoadImageOptionalがNoneを出力して、
# last_frameは未指定扱いになり、
# 開始フレームのみの成り行き生成になる。
#
# モデル構成とサンプリング設定はanime-videoと同じ。
# MiniMax H3にlightx2vの8ステップ蒸留LoRAを効かせて、8ステップで生成する。
#
# 新区間の先頭フレームは元動画の最終フレームとほぼ同じ絵になるが、取り除かずにそのまま連結する。
# 1フレームの重複をなくすことより、区間の映像と音声の長さに手を入れない単純さを取る。
#
# 動きの指示は日本語で書けば自作カスタムノードで英語へ翻訳される。
# 「続きから」の指示なので直前の動きから繋がる動作を書くと自然になる。
# 出力は自作保存ノードによるSVT-AV1 losslessの映像とOpusの音声のWebM。
# 新区間のみと、繋ぎ目を確認するための連結済み動画を別々に保存する。
# 新区間を個別に保存するのは、
# 延長を繰り返すと連結済み動画がComfyUIのアップロード上限を超えるためと、
# 連結済み動画を入力に使い続けると音声の再エンコードによる劣化が重なるため。
# 8-bit RGBから10-bit YUV 4:2:0への色変換後の映像を可逆圧縮する。
# 色変換とクロマサブサンプリングを挟むため、元のRGB画像に対する厳密な可逆圧縮ではない。
{ lib, ... }:
let
  name = "anime-video-extend";
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
    mkFilenamePrefixWith
    seedWidgets
    ;
  # 実写や3Dへ寄るのを避けるために常にプロンプトへ前置するスタイル指定。
  # anime-videoと同じ値。
  animeStylePrefix = "Anime style, 2D cel animation, flat colors.";
in
{
  local.comfyui.workflows.${name} = mkWorkflow {
    app = {
      inputs = [
        (mkAppInput 9 "file")
        (mkAppInputWith 27 "image" {
          description = "任意。延長区間の最後に到達させたいポーズ";
        })
        (mkAppInputWith 19 "text" {
          height = 160;
          description = "続きの動きとカメラワークと音。日本語でも英語でも入力可能";
        })
        (mkAppInput 13 "noise_seed")
      ];
      outputs = [
        17
        28
      ];
    };
    nodes = [
      (mkNode {
        id = 1;
        type = "UNETLoader";
        title = "MiniMax H3モデル";
        pos = [
          1280
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
        id = 29;
        type = "LoraLoaderModelOnly";
        title = "8ステップ蒸留LoRA";
        pos = [
          1280
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
        id = 30;
        title = "LoRA";
        pos = [
          1280
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
          1280
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
          820
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
          820
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
        id = 31;
        type = "VAELoader";
        title = "音声のVAE";
        pos = [
          820
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
      # 動画を読み込むとプレビューがここより下へ展開されて伸びる。
      # その分の場所は`lib/overlap.nix`の`growHeights`が見込んで空けさせている。
      (mkNode {
        id = 9;
        type = "LoadVideo";
        title = "延長する動画";
        pos = [
          (-40)
          650
        ];
        size = [
          340
          310
        ];
        order = 7;
        outputs = [ (mkOutput "VIDEO" "VIDEO" [ 10 ]) ];
        widgets = [ "example.webm" ];
      })
      # 区間の終了時点のポーズを指定する任意入力。
      # 自作のLoadImageOptionalで、(none)のままなら未指定扱いになる。
      # 元動画と同じキャラ・同じ画風・同じアスペクト比の画像を使う。
      (mkNode {
        id = 27;
        type = "LoadImageOptional";
        title = "終了ポーズの画像(任意)";
        pos = [
          (-40)
          280
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
      (mkNode {
        id = 23;
        type = "GetVideoComponents";
        pos = [
          440
          560
        ];
        size = [
          240
          106
        ];
        order = 9;
        inputs = [ (mkInput "video" "VIDEO" 10) ];
        outputs = [
          (mkOutput "images" "IMAGE" [
            12
            13
          ])
          (mkOutput "audio" "AUDIO" [ 14 ])
          (mkOutput "fps" "FLOAT" [ ])
          (mkOutput "bit_depth" "COMBO" [ ])
          (mkOutput "color_space" "COMBO" [ ])
        ];
      })
      # batch_index -1は末尾からの参照。
      (mkNode {
        id = 24;
        type = "ImageFromBatch";
        title = "最終フレームを取り出す";
        pos = [
          440
          730
        ];
        size = [
          315
          106
        ];
        order = 10;
        inputs = [ (mkInput "image" "IMAGE" 12) ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 15 ]) ];
        widgets = [
          (-1) # batch_index
          1 # length
        ];
      })
      # 元動画は生成時に既に768p相当・32の倍数になっているので、
      # このスケールは実質恒等変換だが、
      # 手動で用意した動画を入れた場合の保険としてanime-videoと同じ経路を通す。
      (mkNode {
        id = 21;
        type = "ImageScaleToTotalPixels";
        title = "生成解像度へスケール";
        pos = [
          820
          480
        ];
        size = [
          315
          130
        ];
        order = 11;
        inputs = [ (mkInput "image" "IMAGE" 15) ];
        outputs = [
          (mkOutput "IMAGE" "IMAGE" [
            16
            17
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
          820
          680
        ];
        size = [
          240
          86
        ];
        order = 12;
        inputs = [ (mkInput "image" "IMAGE" 17) ];
        outputs = [
          (mkOutput "width" "INT" [ 18 ])
          (mkOutput "height" "INT" [ 19 ])
          (mkOutput "batch_size" "INT" [ ])
        ];
      })
      # 続きの動きの指示をここに書く。
      # 日本語で書けば英語へ翻訳され、英語で書けばほぼそのまま通る。
      (mkNode {
        id = 19;
        type = "TranslateTextToEnglish";
        title = "続きの動きの指示(日本語でも英語でも可)";
        pos = [
          (-40)
          40
        ];
        size = [
          420
          200
        ];
        order = 13;
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
          440
          40
        ];
        size = [
          340
          130
        ];
        order = 14;
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
          440
          240
        ];
        size = [
          340
          200
        ];
        order = 15;
        inputs = [ (mkInput "source" "*" 22) ];
      })
      # 指示文と元動画の最終フレームから条件付けと空のlatentを作る。
      # latentは映像と音声を1つにまとめたもので、
      # サンプリングの後でそれぞれのVAEが自分の分だけを取り出して復元する。
      # last_frameは任意入力で、終了ポーズ画像が指定されている時だけ、
      # 末尾フレームが指定画像へ固定される。
      # 解像度はソケット経由で自動で入るので手動調整は不要。
      (mkNode {
        id = 12;
        type = "MiniMaxH3ImageToVideo";
        pos = [
          820
          840
        ];
        size = [
          400
          300
        ];
        order = 16;
        inputs = [
          (mkInput "clip" "CLIP" 6)
          (mkInput "vae" "VAE" 7)
          (mkInput "first_frame" "IMAGE" 16 // { shape = 7; })
          (mkInput "last_frame" "IMAGE" 11 // { shape = 7; })
          (mkWidgetInput "prompt" "STRING" 21)
          (mkWidgetInput "width" "INT" 18)
          (mkWidgetInput "height" "INT" 19)
        ];
        outputs = [
          (mkOutput "positive" "CONDITIONING" [ 23 ])
          (mkOutput "LATENT" "LATENT" [ 24 ])
        ];
        widgets = [
          "" # prompt(ソケットから上書きされる)
          1344 # width(ソケットから上書きされる)
          768 # height(ソケットから上書きされる)
          124 # length: 24fpsで約5秒
        ];
      })
      (mkNode {
        id = 13;
        type = "RandomNoise";
        pos = [
          1740
          40
        ];
        size = [
          315
          82
        ];
        order = 17;
        outputs = [ (mkOutput "NOISE" "NOISE" [ 25 ]) ];
        widgets = seedWidgets;
      })
      (mkNode {
        id = 32;
        type = "KSamplerSelect";
        pos = [
          1740
          190
        ];
        size = [
          315
          58
        ];
        order = 18;
        outputs = [ (mkOutput "SAMPLER" "SAMPLER" [ 26 ]) ];
        widgets = [ "res_multistep" ];
      })
      # ステップ数は蒸留LoRAの推奨の8。
      (mkNode {
        id = 33;
        type = "BasicScheduler";
        pos = [
          1740
          320
        ];
        size = [
          315
          106
        ];
        order = 19;
        inputs = [ (mkInput "model" "MODEL" 4) ];
        outputs = [ (mkOutput "SIGMAS" "SIGMAS" [ 27 ]) ];
        widgets = [
          "simple" # scheduler
          8 # steps
          1 # denoise
        ];
      })
      (mkNode {
        id = 34;
        type = "BasicGuider";
        pos = [
          1740
          500
        ];
        size = [
          240
          46
        ];
        order = 20;
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
          1740
          620
        ];
        size = [
          355
          106
        ];
        order = 21;
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
          2160
          40
        ];
        size = [
          210
          46
        ];
        order = 22;
        inputs = [
          (mkInput "samples" "LATENT" 29)
          (mkInput "vae" "VAE" 8)
        ];
        outputs = [
          (mkOutput "IMAGE" "IMAGE" [
            33
            34
          ])
        ];
      })
      (mkNode {
        id = 35;
        type = "VAEDecodeAudio";
        pos = [
          2160
          160
        ];
        size = [
          210
          46
        ];
        order = 23;
        inputs = [
          (mkInput "samples" "LATENT" 30)
          (mkInput "vae" "VAE" 9)
        ];
        outputs = [
          (mkOutput "AUDIO" "AUDIO" [
            35
            36
          ])
        ];
      })
      # 新区間だけを保存する。
      # 連結済み動画の保存とはグラフ上のデータ依存を持たない独立した出力。
      (mkNode {
        id = 28;
        type = "SaveSvtAv1";
        title = "新区間のみを保存";
        pos = [
          2540
          40
        ];
        size = [
          420
          470
        ];
        order = 24;
        inputs = [
          (mkInput "images" "IMAGE" 33)
          (mkInput "audio" "AUDIO" 35 // { shape = 7; })
        ];
        widgets = [
          (mkFilenamePrefixWith name "-segment") # filename_prefix
          24 # fps
          4 # preset
        ];
      })
      # 元動画のフレーム列の後ろへ新区間を連結する。
      (mkNode {
        id = 26;
        type = "BatchImagesNode";
        title = "元動画と連結";
        pos = [
          2160
          280
        ];
        size = [
          240
          78
        ];
        order = 25;
        inputs = [
          (mkInput "images.image0" "IMAGE" 13)
          (mkInput "images.image1" "IMAGE" 34)
        ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 37 ]) ];
      })
      # 元動画の音声の後ろへ新区間の音声を連結する。
      (mkNode {
        id = 37;
        type = "AudioConcat";
        title = "元動画の音声と連結";
        pos = [
          2160
          430
        ];
        size = [
          315
          82
        ];
        order = 26;
        inputs = [
          (mkInput "audio1" "AUDIO" 14)
          (mkInput "audio2" "AUDIO" 36)
        ];
        outputs = [ (mkOutput "AUDIO" "AUDIO" [ 38 ]) ];
        widgets = [ "after" ]; # direction
      })
      # MiniMax H3は24fpsで学習されているのでfpsは24のまま使う。
      (mkNode {
        id = 17;
        type = "SaveSvtAv1";
        title = "連結済み動画を保存";
        pos = [
          2540
          560
        ];
        size = [
          420
          470
        ];
        order = 27;
        inputs = [
          (mkInput "images" "IMAGE" 37)
          (mkInput "audio" "AUDIO" 38 // { shape = 7; })
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
        29
        0
        "MODEL"
      ]
      [
        2
        29
        0
        30
        0
        "MODEL"
      ]
      [
        3
        30
        0
        7
        0
        "MODEL"
      ]
      [
        4
        7
        0
        33
        0
        "MODEL"
      ]
      [
        5
        7
        0
        34
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
        31
        0
        35
        1
        "VAE"
      ]
      [
        10
        9
        0
        23
        0
        "VIDEO"
      ]
      [
        11
        27
        0
        12
        3
        "IMAGE"
      ]
      [
        12
        23
        0
        24
        0
        "IMAGE"
      ]
      [
        13
        23
        0
        26
        0
        "IMAGE"
      ]
      [
        14
        23
        1
        37
        0
        "AUDIO"
      ]
      [
        15
        24
        0
        21
        0
        "IMAGE"
      ]
      [
        16
        21
        0
        12
        2
        "IMAGE"
      ]
      [
        17
        21
        0
        22
        0
        "IMAGE"
      ]
      [
        18
        22
        0
        12
        5
        "INT"
      ]
      [
        19
        22
        1
        12
        6
        "INT"
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
        34
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
        32
        0
        14
        2
        "SAMPLER"
      ]
      [
        27
        33
        0
        14
        3
        "SIGMAS"
      ]
      [
        28
        34
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
        35
        0
        "LATENT"
      ]
      [
        33
        15
        0
        28
        0
        "IMAGE"
      ]
      [
        34
        15
        0
        26
        1
        "IMAGE"
      ]
      [
        35
        35
        0
        28
        1
        "AUDIO"
      ]
      [
        36
        35
        0
        37
        1
        "AUDIO"
      ]
      [
        37
        26
        0
        17
        0
        "IMAGE"
      ]
      [
        38
        37
        0
        17
        1
        "AUDIO"
      ]
    ];
  };
}
