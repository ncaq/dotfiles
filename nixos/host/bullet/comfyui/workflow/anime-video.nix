# アニメ調イラスト1枚をWan 2.2 14B I2Vで動画にするワークフロー。
#
# 公式テンプレートvideo_wan2_2_14B_i2vのLightning LoRA有効構成を、
# サブグラフや切り替えスイッチを除いてフラットに展開したもの。
# high noise→low noiseの2つのexpertモデルをKSamplerAdvanced 2段で使い分ける。
# lightx2v 4steps LoRAで4ステップ・CFG 1の高速生成にしている。
#
# Wan 2.2は実写方向へのバイアスが強く、
# アニメ絵を入力すると実写風に崩れたり動かなかったりしやすい。
# 対策としてポジティブプロンプトの先頭にアニメスタイル指定を固定で結合する。
# CFG 1ではネガティブプロンプトは効かないが、
# CFGを上げて品質重視にする時のために実写抑制語を入れてある。
#
# 生成解像度は入力画像から自動で決まる。
# アスペクト比を保ったまま総ピクセル量0.9メガピクセル(720p相当)へスケールして、
# 16の倍数へ丸めた実寸をWanImageToVideoへ渡す。
#
# 品質重視にする場合はLightning LoRAの2ノードをバイパスして、
# 両方のKSamplerAdvancedをsteps 20(切り替え点10)、cfg 3.5にする。
#
# 動画の長さは「窓の数」で指定する。
# Wanは81フレーム(16fpsで約5秒)前後の長さで学習されていて、
# それを超える長さを一度に生成すると動きが逆再生のように戻ってしまうため、
# Wan Context Windowsで81フレームの窓に分割してサンプリングする。
# 窓は56フレームずつ進むので窓の数nで長さは81+56*(n-1)フレームになる。
# 窓1枚なら分割は発動せず品質への影響はない。
# コアのMath Expressionノードが窓の数からフレーム数を計算して、
# WanImageToVideoのlengthへソケットで渡す。
#
# 動きの指示は日本語で書けば自作カスタムノードで英語へ翻訳される。
# カメラワーク(近づく、回り込むなど)と動作を具体的に書くと動きが出やすい。
# 出力はSVT-AV1のMP4。CRF 1で劣化を最小化しているが、
# 4:2:0への色変換があるため厳密な可逆圧縮ではない。
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
  animeStylePrefix = "Anime style, 2D cel animation, flat colors.";
  # 公式テンプレートのネガティブに実写抑制を追記したもの。
  negativePrompt = "色调艳丽，过曝，静态，细节模糊不清，字幕，风格，作品，画作，画面，静止，整体发灰，最差质量，低质量，JPEG压缩残留，丑陋的，残缺的，多余的手指，画得不好的手部，画得不好的脸部，畸形的，毁容的，形态畸形的肢体，手指融合，静止不动的画面，杂乱的背景，三条腿，背景人很多，倒着走，写实风格，照片级，3D渲染，真人";
in
{
  local.comfyui.workflows.anime-video = mkWorkflow {
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
        type = "LoadImage";
        title = "動かす画像";
        pos = [
          (-40)
          620
        ];
        size = [
          340
          314
        ];
        order = 4;
        outputs = [
          (mkOutput "IMAGE" "IMAGE" [ 11 ])
          (mkOutput "MASK" "MASK" [ ])
        ];
        widgets = [
          "example.png"
          "image"
        ];
      })
      # アスペクト比を保って0.9メガピクセルへスケールしつつ、
      # 幅と高さをWanの要求する16の倍数へ丸める。
      # 生成を速くしたい時はmegapixelsを0.5などへ下げる。
      (mkNode {
        id = 21;
        type = "ImageScaleToTotalPixels";
        title = "生成解像度へスケール";
        pos = [
          (-40)
          1020
        ];
        size = [
          315
          130
        ];
        order = 5;
        inputs = [ (mkInput "image" "IMAGE" 11) ];
        outputs = [
          (mkOutput "IMAGE" "IMAGE" [
            26
            27
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
        order = 6;
        inputs = [ (mkInput "image" "IMAGE" 27) ];
        outputs = [
          (mkOutput "width" "INT" [ 28 ])
          (mkOutput "height" "INT" [ 29 ])
          (mkOutput "batch_size" "INT" [ ])
        ];
      })
      # 動画の長さを窓の数で指定する。
      # 1窓で約5秒、以降1窓ごとに約3.5秒伸びる。
      (mkNode {
        id = 25;
        type = "PrimitiveInt";
        title = "動画の長さ: 1窓約5秒、1窓ごとに+約3.5秒";
        pos = [
          (-40)
          1220
        ];
        size = [
          460
          106
        ];
        order = 22;
        outputs = [ (mkOutput "INT" "INT" [ 32 ]) ];
        widgets = [
          1 # value
          "fixed" # control_after_generate
        ];
      })
      # WanImageToVideoのlengthへ渡すフレーム数を窓の数aから計算する。
      # 定数81と56はコンテキスト窓ノードのcontext_length 81と、
      # overlap 30(latent単位で7に丸められ進み幅はlatent 14=56フレーム)由来なので、
      # そちらを変える時は揃えること。
      # 81も56もWanの要求する4n+1のフレーム数を保つ値になっている。
      (mkNode {
        id = 24;
        type = "ComfyMathExpression";
        title = "フレーム数を計算";
        pos = [
          580
          1220
        ];
        size = [
          315
          106
        ];
        order = 23;
        inputs = [
          (mkInput "values.a" "FLOAT,INT,BOOLEAN" 32)
          # autogrowの次の空きスロット。shape 7はoptionalの意味。
          (
            mkInput "values.b" "FLOAT,INT,BOOLEAN" null
            // {
              shape = 7;
            }
          )
        ];
        outputs = [
          (mkOutput "FLOAT" "FLOAT" [ ])
          (mkOutput "INT" "INT" [
            31
            35
          ])
          (mkOutput "BOOL" "BOOLEAN" [ ])
        ];
        widgets = [ "81 + 56 * (max(1, a) - 1)" ];
      })
      # フレーム数を16fpsの秒数へ換算する。実行時の表示用。
      (mkNode {
        id = 28;
        type = "ComfyMathExpression";
        title = "フレーム数を秒数へ換算";
        pos = [
          940
          1220
        ];
        size = [
          315
          106
        ];
        order = 24;
        inputs = [
          (mkInput "values.a" "FLOAT,INT,BOOLEAN" 35)
          # autogrowの次の空きスロット。shape 7はoptionalの意味。
          (
            mkInput "values.b" "FLOAT,INT,BOOLEAN" null
            // {
              shape = 7;
            }
          )
        ];
        outputs = [
          (mkOutput "FLOAT" "FLOAT" [ 36 ])
          (mkOutput "INT" "INT" [ ])
          (mkOutput "BOOL" "BOOLEAN" [ ])
        ];
        widgets = [ "round(a / 16 * 10) / 10" ];
      })
      # 実行時に実際の秒数を表示する。
      # ノードのタイトルやウィジェットを入力に応じてリアルタイムに書き換えるには、
      # フロントエンドのJavaScript拡張が必要なため実行時表示で妥協している。
      (mkNode {
        id = 29;
        type = "PreviewAny";
        title = "実際の動画の長さ(秒)";
        pos = [
          1300
          1220
        ];
        size = [
          240
          106
        ];
        order = 25;
        inputs = [ (mkInput "source" "*" 36) ];
      })
      # 動きの指示をここに書く。
      # 日本語で書けば英語へ翻訳され、英語で書けばほぼそのまま通る。
      (mkNode {
        id = 19;
        type = "TranslateTextToEnglish";
        title = "動きの指示(日本語でも英語でも可)";
        pos = [
          (-40)
          (-220)
        ];
        size = [
          420
          200
        ];
        order = 7;
        outputs = [ (mkOutput "english_text" "STRING" [ 23 ]) ];
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
        order = 8;
        inputs = [
          (
            mkInput "string_b" "STRING" 23
            // {
              widget = {
                name = "string_b";
              };
            }
          )
        ];
        outputs = [
          (mkOutput "STRING" "STRING" [
            24
            25
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
        order = 9;
        inputs = [ (mkInput "source" "*" 25) ];
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
        order = 10;
        inputs = [
          (mkInput "clip" "CLIP" 3)
          (
            mkInput "text" "STRING" 24
            // {
              widget = {
                name = "text";
              };
            }
          )
        ];
        outputs = [ (mkOutput "CONDITIONING" "CONDITIONING" [ 12 ]) ];
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
        order = 11;
        inputs = [ (mkInput "clip" "CLIP" 4) ];
        outputs = [ (mkOutput "CONDITIONING" "CONDITIONING" [ 13 ]) ];
        widgets = [ negativePrompt ];
      })
      # スケール済み画像から初期latentを作る。
      # 解像度はソケット経由で自動で入るので手動調整は不要。
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
        order = 12;
        inputs = [
          (mkInput "positive" "CONDITIONING" 12)
          (mkInput "negative" "CONDITIONING" 13)
          (mkInput "vae" "VAE" 5)
          (mkInput "clip_vision_output" "CLIP_VISION_OUTPUT" null)
          (mkInput "start_image" "IMAGE" 26)
          (
            mkInput "width" "INT" 28
            // {
              widget = {
                name = "width";
              };
            }
          )
          (
            mkInput "height" "INT" 29
            // {
              widget = {
                name = "height";
              };
            }
          )
          (
            mkInput "length" "INT" 31
            // {
              widget = {
                name = "length";
              };
            }
          )
        ];
        outputs = [
          (mkOutput "positive" "CONDITIONING" [
            14
            15
          ])
          (mkOutput "negative" "CONDITIONING" [
            16
            17
          ])
          (mkOutput "latent" "LATENT" [ 18 ])
        ];
        widgets = [
          704 # width(ソケットから上書きされる)
          1280 # height(ソケットから上書きされる)
          81 # length(フレーム数計算ノードから上書きされる)
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
        order = 13;
        inputs = [ (mkInput "model" "MODEL" 1) ];
        outputs = [ (mkOutput "MODEL" "MODEL" [ 7 ]) ];
        widgets = [
          "wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors"
          1 # strength_model
        ];
      })
      (mkNode {
        id = 6;
        type = "LoraLoaderModelOnly";
        title = "Lightning LoRA(low)";
        pos = [
          960
          620
        ];
        size = [
          315
          82
        ];
        order = 14;
        inputs = [ (mkInput "model" "MODEL" 2) ];
        outputs = [ (mkOutput "MODEL" "MODEL" [ 8 ]) ];
        widgets = [
          "wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors"
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
        order = 15;
        inputs = [ (mkInput "model" "MODEL" 7) ];
        outputs = [ (mkOutput "MODEL" "MODEL" [ 9 ]) ];
        widgets = [ 5 ]; # shift
      })
      (mkNode {
        id = 8;
        type = "ModelSamplingSD3";
        title = "shift(low)";
        pos = [
          960
          760
        ];
        size = [
          315
          58
        ];
        order = 16;
        inputs = [ (mkInput "model" "MODEL" 8) ];
        outputs = [ (mkOutput "MODEL" "MODEL" [ 10 ]) ];
        widgets = [ 5 ]; # shift
      })
      # 学習範囲の81フレームの窓に分割してサンプリングして、
      # 長尺指定時に動きが逆再生のように戻るのを防ぐ。
      # 81フレーム以下では発動せず素通しになる。
      # 一度に扱うlatentも窓の分だけになるのでVRAM消費も抑えられる。
      #
      # retain_first_frameは開始画像の条件を全ての窓に保持させる。
      # 無効だと2枚目以降の窓が開始画像を見ずに生成され、
      # 窓の切り替わりでキャラの顔や塗りが別物にすり替わる。
      (mkNode {
        id = 26;
        type = "WanContextWindowsManual";
        title = "コンテキスト窓(high)";
        pos = [
          960
          320
        ];
        size = [
          330
          200
        ];
        order = 25;
        inputs = [ (mkInput "model" "MODEL" 9) ];
        outputs = [ (mkOutput "MODEL" "MODEL" [ 33 ]) ];
        widgets = [
          81 # context_length
          30 # context_overlap
          "standard_uniform" # context_schedule
          1 # context_stride
          false # closed_loop
          "pyramid" # fuse_method
          true # freenoise
          true # retain_first_frame
          false # split_conds_to_windows
        ];
      })
      (mkNode {
        id = 27;
        type = "WanContextWindowsManual";
        title = "コンテキスト窓(low)";
        pos = [
          960
          900
        ];
        size = [
          330
          200
        ];
        order = 26;
        inputs = [ (mkInput "model" "MODEL" 10) ];
        outputs = [ (mkOutput "MODEL" "MODEL" [ 34 ]) ];
        widgets = [
          81 # context_length
          30 # context_overlap
          "standard_uniform" # context_schedule
          1 # context_stride
          false # closed_loop
          "pyramid" # fuse_method
          true # freenoise
          true # retain_first_frame
          false # split_conds_to_windows
        ];
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
        order = 17;
        inputs = [
          (mkInput "model" "MODEL" 33)
          (mkInput "positive" "CONDITIONING" 14)
          (mkInput "negative" "CONDITIONING" 16)
          (mkInput "latent_image" "LATENT" 18)
        ];
        outputs = [ (mkOutput "LATENT" "LATENT" [ 19 ]) ];
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
          620
        ];
        size = [
          315
          334
        ];
        order = 18;
        inputs = [
          (mkInput "model" "MODEL" 34)
          (mkInput "positive" "CONDITIONING" 15)
          (mkInput "negative" "CONDITIONING" 17)
          (mkInput "latent_image" "LATENT" 19)
        ];
        outputs = [ (mkOutput "LATENT" "LATENT" [ 20 ]) ];
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
          620
        ];
        size = [
          210
          46
        ];
        order = 19;
        inputs = [
          (mkInput "samples" "LATENT" 20)
          (mkInput "vae" "VAE" 6)
        ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 21 ]) ];
      })
      # Wan 2.2 14Bは16fpsで学習されているのでfpsは16のまま使う。
      (mkNode {
        id = 17;
        type = "SaveAv1Mp4";
        pos = [
          1780
          620
        ];
        size = [
          420
          470
        ];
        order = 20;
        inputs = [ (mkInput "images" "IMAGE" 21) ];
        widgets = [
          "anime-video" # filename_prefix
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
        26
        0
        "MODEL"
      ]
      [
        10
        8
        0
        27
        0
        "MODEL"
      ]
      [
        11
        9
        0
        21
        0
        "IMAGE"
      ]
      [
        12
        10
        0
        12
        0
        "CONDITIONING"
      ]
      [
        13
        11
        0
        12
        1
        "CONDITIONING"
      ]
      [
        14
        12
        0
        13
        1
        "CONDITIONING"
      ]
      [
        15
        12
        0
        14
        1
        "CONDITIONING"
      ]
      [
        16
        12
        1
        13
        2
        "CONDITIONING"
      ]
      [
        17
        12
        1
        14
        2
        "CONDITIONING"
      ]
      [
        18
        12
        2
        13
        3
        "LATENT"
      ]
      [
        19
        13
        0
        14
        3
        "LATENT"
      ]
      [
        20
        14
        0
        15
        0
        "LATENT"
      ]
      [
        21
        15
        0
        17
        0
        "IMAGE"
      ]
      [
        23
        19
        0
        18
        0
        "STRING"
      ]
      [
        24
        18
        0
        10
        1
        "STRING"
      ]
      [
        25
        18
        0
        20
        0
        "STRING"
      ]
      [
        26
        21
        0
        12
        4
        "IMAGE"
      ]
      [
        27
        21
        0
        22
        0
        "IMAGE"
      ]
      [
        28
        22
        0
        12
        5
        "INT"
      ]
      [
        29
        22
        1
        12
        6
        "INT"
      ]
      [
        31
        24
        1
        12
        7
        "INT"
      ]
      [
        32
        25
        0
        24
        0
        "INT"
      ]
      [
        35
        24
        1
        28
        0
        "INT"
      ]
      [
        36
        28
        0
        29
        0
        "FLOAT"
      ]
      [
        33
        26
        0
        13
        0
        "MODEL"
      ]
      [
        34
        27
        0
        14
        0
        "MODEL"
      ]
    ];
  };
}
