# アニメ動画をSeedVR2 7B FP16で4Kへアップスケールするワークフロー。
#
# SeedVR2は短辺をresolutionへ合わせてアスペクト比を維持する。
# ImageScaleで最後に3840x2160へ厳密に合わせるため、
# 入力が16:9でない場合は変形する。幅と高さは素材の比率に合わせて変更すること。
#
# RTX 5090の32GB VRAMで7B FP16を安定して動かすため、
# DiTの16ブロックとI/O部品をCPUへ退避し、VAEはタイル処理する。
# VRAMに余裕があればblocks_to_swapを減らすと高速になる。
#
# 自作保存ノードはRGB48から10-bit SVT-AV1へ変換し、音声をFLACで格納する。
# CRF 1はnear-losslessだが、4:2:0への色差変換があるため厳密な可逆圧縮ではない。
{ lib, ... }:
let
  name = "anime-video-upscale";
  inherit (import ./lib/builder.nix { inherit lib; })
    mkNode
    mkInput
    mkOutput
    mkAppInput
    mkAppInputWith
    mkWorkflow
    mkFilenamePrefix
    ;
in
{
  local.comfyui.workflows.${name} = mkWorkflow {
    app = {
      inputs = [
        (mkAppInput 1 "file")
        (mkAppInputWith 6 "width" {
          description = "出力動画の幅";
        })
        (mkAppInputWith 6 "height" {
          description = "出力動画の高さ";
        })
      ];
      outputs = [ 9 ];
    };
    nodes = [
      (mkNode {
        id = 1;
        type = "LoadVideo";
        title = "アップスケールする動画";
        pos = [
          (-40)
          80
        ];
        size = [
          340
          310
        ];
        order = 0;
        outputs = [ (mkOutput "VIDEO" "VIDEO" [ 1 ]) ];
        widgets = [
          "example.mp4"
          "image"
        ];
      })
      (mkNode {
        id = 2;
        type = "GetVideoComponents";
        pos = [
          380
          80
        ];
        size = [
          240
          106
        ];
        order = 1;
        inputs = [ (mkInput "video" "VIDEO" 1) ];
        outputs = [
          (mkOutput "images" "IMAGE" [ 2 ])
          (mkOutput "audio" "AUDIO" [ 8 ])
          (mkOutput "fps" "FLOAT" [ 9 ])
          (mkOutput "bit_depth" "INT" [ ])
        ];
      })
      (mkNode {
        id = 3;
        type = "SeedVR2LoadDiTModel";
        title = "SeedVR2 7B FP16";
        pos = [
          380
          300
        ];
        size = [
          390
          250
        ];
        order = 2;
        outputs = [ (mkOutput "SEEDVR2_DIT" "SEEDVR2_DIT" [ 3 ]) ];
        widgets = [
          "seedvr2_ema_7b_fp16.safetensors"
          "cuda:0"
          16 # blocks_to_swap
          true # swap_io_components
          "cpu" # offload_device
          true # cache_model
          "sdpa" # attention_mode: 品質と互換性を優先
        ];
      })
      (mkNode {
        id = 4;
        type = "SeedVR2LoadVAEModel";
        title = "SeedVR2 VAE FP16 tiled";
        pos = [
          380
          650
        ];
        size = [
          390
          330
        ];
        order = 3;
        outputs = [ (mkOutput "SEEDVR2_VAE" "SEEDVR2_VAE" [ 4 ]) ];
        widgets = [
          "ema_vae_fp16.safetensors"
          "cuda:0"
          true # encode_tiled
          1024 # encode_tile_size
          128 # encode_tile_overlap
          true # decode_tiled
          768 # decode_tile_size
          128 # decode_tile_overlap
          "false" # tile_debug
          "cpu" # offload_device
          true # cache_model
        ];
      })
      (mkNode {
        id = 5;
        type = "SeedVR2VideoUpscaler";
        title = "時間的一貫性を保って4K化";
        pos = [
          900
          180
        ];
        size = [
          360
          430
        ];
        order = 4;
        inputs = [
          (mkInput "image" "IMAGE" 2)
          (mkInput "dit" "SEEDVR2_DIT" 3)
          (mkInput "vae" "SEEDVR2_VAE" 4)
        ];
        outputs = [ (mkOutput "IMAGE" "IMAGE" [ 5 ]) ];
        widgets = [
          42
          "fixed"
          2160 # resolution: short edge
          3840 # max_resolution
          5 # batch_size: 4n+1
          true # uniform_batch_size
          3 # temporal_overlap
          0 # prepend_frames
          "lab" # color_correction
          0 # input_noise_scale
          0 # latent_noise_scale
          "cpu" # offload_device
          false # enable_debug
        ];
      })
      (mkNode {
        id = 6;
        type = "ImageScale";
        title = "指定解像度へ仕上げ(16:9以外は要変更)";
        pos = [
          1340
          180
        ];
        size = [
          360
          190
        ];
        order = 5;
        inputs = [ (mkInput "image" "IMAGE" 5) ];
        outputs = [
          (mkOutput "IMAGE" "IMAGE" [
            10
          ])
        ];
        widgets = [
          "lanczos"
          3840 # width
          2160 # height
          "disabled" # crop
        ];
      })
      (mkNode {
        id = 9;
        type = "SaveSvtAv1";
        title = "SVT-AV1 near-lossless + FLAC";
        pos = [
          1780
          180
        ];
        size = [
          420
          280
        ];
        order = 6;
        inputs = [
          (mkInput "images" "IMAGE" 10)
          (mkInput "fps" "FLOAT" 9) # widget metadataはフロントエンドがSaveSvtAv1の入力定義から復元
          (mkInput "audio" "AUDIO" 8)
        ];
        outputs = [ ];
        widgets = [
          24 # fpsはリンクで上書きされる
          (mkFilenamePrefix name) # filename_prefix
          1 # CRF: near-lossless
          4 # preset: 品質優先
        ];
      })
      (mkNode {
        id = 10;
        type = "Note";
        pos = [
          1780
          540
        ];
        size = [
          420
          250
        ];
        order = 7;
        widgets = [
          "元fpsとAUDIOバッチ先頭の音声を維持し、映像長へ切り詰めてFLACで保存する。1から8チャンネルは維持し、それ以上はmonoへ変換する。映像はSVT-AV1 10-bit CRF 1でMKVへ保存する。字幕、チャプター、複数音声、添付フォントまで維持する場合は、出力映像を元MKVとmkvmergeで再muxする。"
        ];
      })
    ];
    links = [
      [
        1
        1
        0
        2
        0
        "VIDEO"
      ]
      [
        2
        2
        0
        5
        0
        "IMAGE"
      ]
      [
        3
        3
        0
        5
        1
        "SEEDVR2_DIT"
      ]
      [
        4
        4
        0
        5
        2
        "SEEDVR2_VAE"
      ]
      [
        5
        5
        0
        6
        0
        "IMAGE"
      ]
      [
        8
        2
        1
        9
        2
        "AUDIO"
      ]
      [
        9
        2
        2
        9
        1
        "FLOAT"
      ]
      [
        10
        6
        0
        9
        0
        "IMAGE"
      ]
    ];
  };
}
