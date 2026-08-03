# 開始画像と1行約5秒の指示列だけから、長尺動画を半自動生成するワークフロー。
#
# 空行は場面境界、空行でない各行は1動画区間として日本語の段階で分割する。
# 各行を個別に英訳し、同じ英文をQwen-Image-Editの終了キーフレーム生成と、
# Wan 2.2 FLF2Vの動画生成へ渡す。
#
# Qwenで全キーフレームを先に生成してからWanの全区間を生成するため、
# モデルの往復を避けられる。画像と動画は区間ごとに即座にファイルへ保存し、
# 全フレームをRAMへ蓄積せず、最後はffmpeg concatで再エンコードせずに結合する。
#
# 出力先のanime-video-quick/<job ID>/manifest.jsonに進捗を記録する。
# 同じ入力とjob IDで再実行すると生成済みファイルを飛ばして途中から再開する。
# 破綻した区間はsegments/anime-video-quick-<job ID>-segment-<番号>.webmを削除して、
# 再実行すればその区間だけ作り直せる。
{ lib, ... }:
let
  name = "anime-video-quick";
  inherit (import ./lib/builder.nix { inherit lib; })
    mkNode
    mkInput
    mkOutput
    mkAppInput
    mkAppInputWith
    mkWorkflow
    ;
in
{
  local.comfyui.workflows.${name} = mkWorkflow {
    app = {
      inputs = [
        (mkAppInput 4 "image")
        (mkAppInputWith 12 "prompts" {
          height = 260;
          description = "空行は場面境界、空行でない1行は約5秒の区間";
        })
        (mkAppInput 12 "seed")
        (mkAppInputWith 12 "retry_seed_offset" {
          description = "破綻区間を削除して再生成する時に増やすseed差分";
        })
        (mkAppInputWith 12 "job_id" {
          description = "空なら日時から自動生成。同じ値で未完了地点から再開";
        })
      ];
      outputs = [ 12 ];
    };
    nodes = [
      (mkNode {
        id = 1;
        type = "UNETLoader";
        title = "Qwen-Image-Editモデル";
        pos = [
          (-40)
          40
        ];
        size = [
          385
          82
        ];
        order = 0;
        outputs = [ (mkOutput "MODEL" "MODEL" [ 1 ]) ];
        widgets = [
          "qwen_image_edit_2511_fp8mixed.safetensors"
          "default"
        ];
      })
      (mkNode {
        id = 2;
        type = "CLIPLoader";
        title = "Qwen画像理解モデル";
        pos = [
          (-40)
          180
        ];
        size = [
          385
          106
        ];
        order = 1;
        outputs = [ (mkOutput "CLIP" "CLIP" [ 3 ]) ];
        widgets = [
          "qwen_2.5_vl_7b.safetensors"
          "qwen_image"
          "default"
        ];
      })
      (mkNode {
        id = 3;
        type = "VAELoader";
        title = "Qwen VAE";
        pos = [
          (-40)
          340
        ];
        size = [
          385
          58
        ];
        order = 2;
        outputs = [ (mkOutput "VAE" "VAE" [ 4 ]) ];
        widgets = [ "qwen_image_vae.safetensors" ];
      })
      (mkNode {
        id = 4;
        type = "LoadImage";
        title = "最初の画像";
        pos = [
          (-40)
          460
        ];
        size = [
          340
          314
        ];
        order = 3;
        outputs = [
          (mkOutput "IMAGE" "IMAGE" [ 5 ])
          (mkOutput "MASK" "MASK" [ ])
        ];
        widgets = [
          "example.png"
          "image"
        ];
      })
      (mkNode {
        id = 5;
        type = "ModelSamplingAuraFlow";
        title = "Qwen shift";
        pos = [
          420
          40
        ];
        size = [
          315
          58
        ];
        order = 4;
        inputs = [ (mkInput "model" "MODEL" 1) ];
        outputs = [ (mkOutput "MODEL" "MODEL" [ 2 ]) ];
        widgets = [ 3.1 ];
      })
      (mkNode {
        id = 6;
        type = "CFGNorm";
        title = "Qwen CFG正規化";
        pos = [
          420
          160
        ];
        size = [
          315
          82
        ];
        order = 5;
        inputs = [ (mkInput "model" "MODEL" 2) ];
        outputs = [ (mkOutput "patched_model" "MODEL" [ 6 ]) ];
        widgets = [
          1
          false
        ];
      })
      (mkNode {
        id = 12;
        type = "AnimeVideoQuick";
        title = "Qwen全画像生成 → Wan全動画生成 → 結合";
        pos = [
          1260
          40
        ];
        size = [
          520
          620
        ];
        order = 6;
        inputs = [
          (mkInput "image" "IMAGE" 5)
          {
            name = "prompts";
            type = "STRING";
            widget = {
              name = "prompts";
            };
            link = null;
          }
          (mkInput "qwen_model" "MODEL" 6)
          (mkInput "qwen_clip" "CLIP" 3)
          (mkInput "qwen_vae" "VAE" 4)
          {
            name = "wan_model_high";
            type = "COMBO";
            widget = {
              name = "wan_model_high";
            };
            link = null;
          }
          {
            name = "wan_model_low";
            type = "COMBO";
            widget = {
              name = "wan_model_low";
            };
            link = null;
          }
          {
            name = "wan_clip";
            type = "COMBO";
            widget = {
              name = "wan_clip";
            };
            link = null;
          }
          {
            name = "wan_vae";
            type = "COMBO";
            widget = {
              name = "wan_vae";
            };
            link = null;
          }
          {
            name = "seed";
            type = "INT";
            widget = {
              name = "seed";
            };
            link = null;
          }
          {
            name = "retry_seed_offset";
            type = "INT";
            widget = {
              name = "retry_seed_offset";
            };
            link = null;
          }
          {
            name = "job_id";
            type = "STRING";
            widget = {
              name = "job_id";
            };
            link = null;
          }
        ];
        outputs = [ (mkOutput "video_path" "STRING" [ ]) ];
        widgets = [
          ''
            キャラクターはゆっくり振り返る。

            カメラへ向かって穏やかに微笑む。
          ''
        ]
        ++ [
          "wan2.2_i2v_A14b_high_noise_lightx2v_4step_720p_260412.safetensors"
          "wan2.2_i2v_A14b_low_noise_lightx2v_4step_720p_260412.safetensors"
          "umt5_xxl_fp16.safetensors"
          "wan_2.1_vae.safetensors"
          0
          "fixed"
          0
          ""
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
        5
        0
        6
        0
        "MODEL"
      ]
      [
        3
        2
        0
        12
        3
        "CLIP"
      ]
      [
        4
        3
        0
        12
        4
        "VAE"
      ]
      [
        5
        4
        0
        12
        0
        "IMAGE"
      ]
      [
        6
        6
        0
        12
        2
        "MODEL"
      ]
    ];
  };
}
