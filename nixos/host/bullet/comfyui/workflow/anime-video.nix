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
# 動きの指示は日本語で書けば自作カスタムノードで英語へ翻訳される。
# カメラワーク(近づく、回り込むなど)と動作を具体的に書くと動きが出やすい。
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
          980
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
          340
          980
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
      # 動きの指示をここに書く。
      # 日本語で書けば英語へ翻訳され、英語で書けばほぼそのまま通る。
      (mkNode {
        id = 19;
        type = "TranslateTextToEnglish";
        title = "動きの指示(日本語でも英語でも可)";
        pos = [
          (-40)
          (-200)
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
          420
          (-200)
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
          800
          (-200)
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
          420
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
          420
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
          420
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
          81 # length: 16fpsで約5秒
          1 # batch_size
        ];
      })
      (mkNode {
        id = 5;
        type = "LoraLoaderModelOnly";
        title = "Lightning LoRA(high)";
        pos = [
          920
          (-60)
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
          920
          60
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
          920
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
          920
          280
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
      # 前半2ステップをhigh noiseモデルで生成する。
      (mkNode {
        id = 13;
        type = "KSamplerAdvanced";
        title = "サンプリング前半(high noise)";
        pos = [
          920
          400
        ];
        size = [
          315
          334
        ];
        order = 17;
        inputs = [
          (mkInput "model" "MODEL" 9)
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
          1290
          400
        ];
        size = [
          315
          334
        ];
        order = 18;
        inputs = [
          (mkInput "model" "MODEL" 10)
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
          1660
          400
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
        id = 16;
        type = "CreateVideo";
        pos = [
          1660
          500
        ];
        size = [
          270
          78
        ];
        order = 20;
        inputs = [
          (mkInput "images" "IMAGE" 21)
          (mkInput "audio" "AUDIO" null)
        ];
        outputs = [ (mkOutput "VIDEO" "VIDEO" [ 22 ]) ];
        widgets = [ 16 ]; # fps
      })
      (mkNode {
        id = 17;
        type = "SaveVideo";
        pos = [
          1940
          400
        ];
        size = [
          420
          470
        ];
        order = 21;
        inputs = [ (mkInput "video" "VIDEO" 22) ];
        widgets = [
          "anime-video" # filename_prefix
          "auto" # format
          "auto" # codec
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
        16
        0
        "IMAGE"
      ]
      [
        22
        16
        0
        17
        0
        "VIDEO"
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
    ];
  };
}
