# anime-videoで生成した動画を約5秒(81フレーム)延長するワークフロー。
#
# anime-videoのコンテキスト窓方式は定常的な動きの長回しには向くが、
# 開始画像の条件を全窓に保持させる都合で窓の切り替わりでポーズが戻りやすく、
# 動画全体で1つの大きな動作をさせるのが難しい。
# こちらは既存動画の最終フレームを開始画像にして続きを生成し、
# 元動画と連結して出力する継ぎ足し方式。
# 各区間の絵は直前の区間の最終ポーズに固定されるため動作が前へ進み、
# 区間ごとに動きの指示を変えて演出できる。
# 結果を確認しながら好きな回数繰り返して延長できる。
#
# 弱点は繋ぎ目で動きの勢いが一瞬失われることと、
# 区間を重ねるごとに色味や質感が少しずつ劣化していくこと。
#
# モデル構成とサンプリング設定はanime-videoと同じ。
# Wan 2.2 14B I2VのLightning LoRA有効構成で、
# 4ステップ・CFG 1の高速生成にしている。
# 1回の延長は学習範囲内の81フレーム固定なのでコンテキスト窓は使わない。
#
# 新区間の先頭フレームは元動画の最終フレームとほぼ同じ絵になるため、
# 連結時に取り除いて一瞬の停滞を防ぐ。
#
# 動きの指示は日本語で書けば自作カスタムノードで英語へ翻訳される。
# 「続きから」の指示なので直前の動きから繋がる動作を書くと自然になる。
# 出力は公式SaveWEBMノードによるSVT-AV1のWebM。
# CRF 1で劣化を最小化しているが、
# 8-bit RGBから4:2:0への色変換があるため厳密な可逆圧縮ではない。
{ lib, ... }:
let
  inherit (import ./lib/builder.nix { inherit lib; })
    mkNode
    mkInput
    mkOutput
    mkWorkflow
    seedWidgets
    ;
  # 実写バイアスを打ち消すために常にプロンプトへ前置するスタイル指定。
  # anime-videoと同じ値。
  animeStylePrefix = "Anime style, 2D cel animation, flat colors.";
  # 公式テンプレートのネガティブに実写抑制を追記したもの。
  # anime-videoと同じ値。
  negativePrompt = "色调艳丽，过曝，静态，细节模糊不清，字幕，风格，作品，画作，画面，静止，整体发灰，最差质量，低质量，JPEG压缩残留，丑陋的，残缺的，多余的手指，画得不好的手部，画得不好的脸部，畸形的，毁容的，形态畸形的肢体，手指融合，静止不动的画面，杂乱的背景，三条腿，背景人很多，倒着走，写实风格，照片级，3D渲染，真人";
in
{
  local.comfyui.workflows.anime-video-extend = mkWorkflow {
    nodes = [
      (mkNode {
        id = 1;
        type = "UNETLoader";
        title = "high noiseモデル";
        pos = [
          (-40)
          60
        ];
        size = [
          385
          82
        ];
        order = 0;
        outputs = [ (mkOutput "MODEL" "MODEL" [ 1 ]) ];
        widgets = [
          "wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors"
          "default" # weight_dtype
        ];
      })
      (mkNode {
        id = 2;
        type = "UNETLoader";
        title = "low noiseモデル";
        pos = [
          (-40)
          200
        ];
        size = [
          385
          82
        ];
        order = 1;
        outputs = [ (mkOutput "MODEL" "MODEL" [ 2 ]) ];
        widgets = [
          "wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors"
          "default" # weight_dtype
        ];
      })
      (mkNode {
        id = 3;
        type = "CLIPLoader";
        pos = [
          (-40)
          340
        ];
        size = [
          385
          106
        ];
        order = 2;
        outputs = [
          (mkOutput "CLIP" "CLIP" [
            3
            4
          ])
        ];
        widgets = [
          "umt5_xxl_fp8_e4m3fn_scaled.safetensors"
          "wan" # type
          "default" # device
        ];
      })
      (mkNode {
        id = 4;
        type = "VAELoader";
        pos = [
          (-40)
          500
        ];
        size = [
          385
          58
        ];
        order = 3;
        outputs = [
          (mkOutput "VAE" "VAE" [
            5
            6
          ])
        ];
        widgets = [ "wan_2.1_vae.safetensors" ];
      })
      (mkNode {
        id = 9;
        type = "LoadVideo";
        title = "延長する動画";
        pos = [
          (-40)
          620
        ];
        size = [
          340
          310
        ];
        order = 4;
        outputs = [ (mkOutput "VIDEO" "VIDEO" [ 11 ]) ];
        widgets = [ "example.webm" ];
      })
      (mkNode {
        id = 23;
        type = "GetVideoComponents";
        pos = [
          (-40)
          1000
        ];
        size = [
          240
          106
        ];
        order = 5;
        inputs = [ (mkInput "video" "VIDEO" 11) ];
        outputs = [
          (mkOutput "images" "IMAGE" [
            12
            13
          ])
          (mkOutput "audio" "AUDIO" [ ])
          (mkOutput "fps" "FLOAT" [ ])
          (mkOutput "bit_depth" "INT" [ ])
        ];
      })
      # batch_index -1は末尾からの参照。
      (mkNode {
        id = 24;
        type = "ImageFromBatch";
        title = "最終フレームを取り出す";
        pos = [
          (-40)
          1180
        ];
        size = [
          315
          106
        ];
        order = 6;
        inputs = [ (mkInput "image" "IMAGE" 12) ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 14 ]) ];
        widgets = [
          (-1) # batch_index
          1 # length
        ];
      })
      # 元動画は生成時に既に0.9メガピクセル・16の倍数になっているので、
      # このスケールは実質恒等変換だが、
      # 手動で用意した動画を入れた場合の保険としてanime-videoと同じ経路を通す。
      (mkNode {
        id = 21;
        type = "ImageScaleToTotalPixels";
        title = "生成解像度へスケール";
        pos = [
          (-40)
          1340
        ];
        size = [
          315
          130
        ];
        order = 7;
        inputs = [ (mkInput "image" "IMAGE" 14) ];
        outputs = [
          (mkOutput "IMAGE" "IMAGE" [
            15
            16
          ])
        ];
        widgets = [
          "lanczos" # upscale_method
          0.9 # megapixels
          16 # resolution_steps
        ];
      })
      # スケール後の実寸をWanImageToVideoへ渡す。
      (mkNode {
        id = 22;
        type = "GetImageSize";
        pos = [
          460
          1040
        ];
        size = [
          240
          86
        ];
        order = 8;
        inputs = [ (mkInput "image" "IMAGE" 16) ];
        outputs = [
          (mkOutput "width" "INT" [ 17 ])
          (mkOutput "height" "INT" [ 18 ])
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
          (-220)
        ];
        size = [
          420
          200
        ];
        order = 9;
        outputs = [ (mkOutput "english_text" "STRING" [ 19 ]) ];
        widgets = [ "カメラはゆっくりと近づく。キャラクターは穏やかに微笑み、髪と服が風に揺れる。" ];
      })
      # アニメスタイル指定を動きの指示の前に固定で結合する。
      (mkNode {
        id = 18;
        type = "StringConcatenate";
        title = "アニメスタイル指定の前置";
        pos = [
          460
          (-220)
        ];
        size = [
          340
          130
        ];
        order = 10;
        inputs = [
          (
            mkInput "string_b" "STRING" 19
            // {
              widget = {
                name = "string_b";
              };
            }
          )
        ];
        outputs = [
          (mkOutput "STRING" "STRING" [
            20
            21
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
          860
          (-220)
        ];
        size = [
          340
          200
        ];
        order = 11;
        inputs = [ (mkInput "source" "*" 21) ];
      })
      (mkNode {
        id = 10;
        type = "CLIPTextEncode";
        title = "ポジティブ(スタイル+動きの指示)";
        pos = [
          460
          340
        ];
        size = [
          420
          160
        ];
        order = 12;
        inputs = [
          (mkInput "clip" "CLIP" 3)
          (
            mkInput "text" "STRING" 20
            // {
              widget = {
                name = "text";
              };
            }
          )
        ];
        outputs = [ (mkOutput "CONDITIONING" "CONDITIONING" [ 22 ]) ];
        widgets = [ "" ];
      })
      # CFG 1のLightning構成では効かないが、
      # CFGを上げた時のために実写抑制込みで置いてある。
      (mkNode {
        id = 11;
        type = "CLIPTextEncode";
        title = "ネガティブ(CFG 1では無効)";
        pos = [
          460
          560
        ];
        size = [
          420
          160
        ];
        order = 13;
        inputs = [ (mkInput "clip" "CLIP" 4) ];
        outputs = [ (mkOutput "CONDITIONING" "CONDITIONING" [ 23 ]) ];
        widgets = [ negativePrompt ];
      })
      # 元動画の最終フレームから初期latentを作る。
      # 解像度はソケット経由で自動で入るので手動調整は不要。
      # 1回の延長は学習範囲内の81フレーム(約5秒)固定。
      (mkNode {
        id = 12;
        type = "WanImageToVideo";
        pos = [
          460
          780
        ];
        size = [
          315
          210
        ];
        order = 14;
        inputs = [
          (mkInput "positive" "CONDITIONING" 22)
          (mkInput "negative" "CONDITIONING" 23)
          (mkInput "vae" "VAE" 5)
          (mkInput "clip_vision_output" "CLIP_VISION_OUTPUT" null)
          (mkInput "start_image" "IMAGE" 15)
          (
            mkInput "width" "INT" 17
            // {
              widget = {
                name = "width";
              };
            }
          )
          (
            mkInput "height" "INT" 18
            // {
              widget = {
                name = "height";
              };
            }
          )
        ];
        outputs = [
          (mkOutput "positive" "CONDITIONING" [
            24
            25
          ])
          (mkOutput "negative" "CONDITIONING" [
            26
            27
          ])
          (mkOutput "latent" "LATENT" [ 28 ])
        ];
        widgets = [
          704 # width(ソケットから上書きされる)
          1280 # height(ソケットから上書きされる)
          81 # length: 16fpsで約5秒
          1 # batch_size
        ];
      })
      (mkNode {
        id = 5;
        type = "LoraLoaderModelOnly";
        title = "Lightning LoRA(high)";
        pos = [
          960
          40
        ];
        size = [
          315
          82
        ];
        order = 15;
        inputs = [ (mkInput "model" "MODEL" 1) ];
        outputs = [ (mkOutput "MODEL" "MODEL" [ 7 ]) ];
        widgets = [
          "wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors"
          1 # strength_model
        ];
      })
      (mkNode {
        id = 7;
        type = "ModelSamplingSD3";
        title = "shift(high)";
        pos = [
          960
          180
        ];
        size = [
          315
          58
        ];
        order = 16;
        inputs = [ (mkInput "model" "MODEL" 7) ];
        outputs = [ (mkOutput "MODEL" "MODEL" [ 9 ]) ];
        widgets = [ 5 ]; # shift
      })
      (mkNode {
        id = 6;
        type = "LoraLoaderModelOnly";
        title = "Lightning LoRA(low)";
        pos = [
          960
          320
        ];
        size = [
          315
          82
        ];
        order = 17;
        inputs = [ (mkInput "model" "MODEL" 2) ];
        outputs = [ (mkOutput "MODEL" "MODEL" [ 8 ]) ];
        widgets = [
          "wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors"
          1 # strength_model
        ];
      })
      (mkNode {
        id = 8;
        type = "ModelSamplingSD3";
        title = "shift(low)";
        pos = [
          960
          460
        ];
        size = [
          315
          58
        ];
        order = 18;
        inputs = [ (mkInput "model" "MODEL" 8) ];
        outputs = [ (mkOutput "MODEL" "MODEL" [ 10 ]) ];
        widgets = [ 5 ]; # shift
      })
      # 前半2ステップをhigh noiseモデルで生成する。
      (mkNode {
        id = 13;
        type = "KSamplerAdvanced";
        title = "サンプリング前半(high noise)";
        pos = [
          1380
          40
        ];
        size = [
          315
          334
        ];
        order = 19;
        inputs = [
          (mkInput "model" "MODEL" 9)
          (mkInput "positive" "CONDITIONING" 24)
          (mkInput "negative" "CONDITIONING" 26)
          (mkInput "latent_image" "LATENT" 28)
        ];
        outputs = [ (mkOutput "LATENT" "LATENT" [ 29 ]) ];
        widgets = [
          "enable" # add_noise
        ]
        ++ seedWidgets
        ++ [
          4 # steps
          1 # cfg
          "euler"
          "simple"
          0 # start_at_step
          2 # end_at_step
          "enable" # return_with_leftover_noise
        ];
      })
      # 後半をlow noiseモデルで仕上げる。
      (mkNode {
        id = 14;
        type = "KSamplerAdvanced";
        title = "サンプリング後半(low noise)";
        pos = [
          1380
          440
        ];
        size = [
          315
          334
        ];
        order = 20;
        inputs = [
          (mkInput "model" "MODEL" 10)
          (mkInput "positive" "CONDITIONING" 25)
          (mkInput "negative" "CONDITIONING" 27)
          (mkInput "latent_image" "LATENT" 29)
        ];
        outputs = [ (mkOutput "LATENT" "LATENT" [ 30 ]) ];
        widgets = [
          "disable" # add_noise
          0 # noise_seed
          "fixed"
          4 # steps
          1 # cfg
          "euler"
          "simple"
          2 # start_at_step
          10000 # end_at_step
          "disable" # return_with_leftover_noise
        ];
      })
      (mkNode {
        id = 15;
        type = "VAEDecode";
        pos = [
          1780
          440
        ];
        size = [
          210
          46
        ];
        order = 21;
        inputs = [
          (mkInput "samples" "LATENT" 30)
          (mkInput "vae" "VAE" 6)
        ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 31 ]) ];
      })
      # 新区間の先頭フレームは元動画の最終フレームとほぼ同じなので、
      # 連結時の一瞬の停滞を防ぐために取り除く。
      # lengthは残数へ自動でクランプされるので大きな値で全フレームを取る。
      (mkNode {
        id = 25;
        type = "ImageFromBatch";
        title = "新区間の先頭フレームを除去";
        pos = [
          1780
          560
        ];
        size = [
          315
          106
        ];
        order = 22;
        inputs = [ (mkInput "image" "IMAGE" 31) ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 32 ]) ];
        widgets = [
          1 # batch_index
          4096 # length
        ];
      })
      # 元動画のフレーム列の後ろへ新区間を連結する。
      # ImageBatchはdeprecated扱いだがコアに連結の代替ノードがない。
      (mkNode {
        id = 26;
        type = "ImageBatch";
        title = "元動画と連結";
        pos = [
          1780
          720
        ];
        size = [
          240
          78
        ];
        order = 23;
        inputs = [
          (mkInput "image1" "IMAGE" 13)
          (mkInput "image2" "IMAGE" 32)
        ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 33 ]) ];
      })
      # Wan 2.2 14Bは16fpsで学習されているのでfpsは16のまま使う。
      (mkNode {
        id = 17;
        type = "SaveWEBM";
        pos = [
          1780
          440
        ];
        size = [
          420
          470
        ];
        order = 24;
        inputs = [ (mkInput "images" "IMAGE" 33) ];
        widgets = [
          "anime-video-extend" # filename_prefix
          "av1" # codec
          16 # fps
          1 # crf
        ];
      })
    ];
    links = [
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
        2
        0
        6
        0
        "MODEL"
      ]
      [
        3
        3
        0
        10
        0
        "CLIP"
      ]
      [
        4
        3
        0
        11
        0
        "CLIP"
      ]
      [
        5
        4
        0
        12
        2
        "VAE"
      ]
      [
        6
        4
        0
        15
        1
        "VAE"
      ]
      [
        7
        5
        0
        7
        0
        "MODEL"
      ]
      [
        8
        6
        0
        8
        0
        "MODEL"
      ]
      [
        9
        7
        0
        13
        0
        "MODEL"
      ]
      [
        10
        8
        0
        14
        0
        "MODEL"
      ]
      [
        11
        9
        0
        23
        0
        "VIDEO"
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
        24
        0
        21
        0
        "IMAGE"
      ]
      [
        15
        21
        0
        12
        4
        "IMAGE"
      ]
      [
        16
        21
        0
        22
        0
        "IMAGE"
      ]
      [
        17
        22
        0
        12
        5
        "INT"
      ]
      [
        18
        22
        1
        12
        6
        "INT"
      ]
      [
        19
        19
        0
        18
        0
        "STRING"
      ]
      [
        20
        18
        0
        10
        1
        "STRING"
      ]
      [
        21
        18
        0
        20
        0
        "STRING"
      ]
      [
        22
        10
        0
        12
        0
        "CONDITIONING"
      ]
      [
        23
        11
        0
        12
        1
        "CONDITIONING"
      ]
      [
        24
        12
        0
        13
        1
        "CONDITIONING"
      ]
      [
        25
        12
        0
        14
        1
        "CONDITIONING"
      ]
      [
        26
        12
        1
        13
        2
        "CONDITIONING"
      ]
      [
        27
        12
        1
        14
        2
        "CONDITIONING"
      ]
      [
        28
        12
        2
        13
        3
        "LATENT"
      ]
      [
        29
        13
        0
        14
        3
        "LATENT"
      ]
      [
        30
        14
        0
        15
        0
        "LATENT"
      ]
      [
        31
        15
        0
        25
        0
        "IMAGE"
      ]
      [
        32
        25
        0
        26
        1
        "IMAGE"
      ]
      [
        33
        26
        0
        17
        0
        "IMAGE"
      ]
    ];
  };
}
