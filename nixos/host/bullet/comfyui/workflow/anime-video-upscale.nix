# アニメ動画をSeedVR2 7B FP16で4Kへアップスケールするワークフロー。
#
# 指定した出力長辺と元動画の比率から幅と高さを自動計算し、
# SeedVR2と保存直前のLanczosスケールへ同じ目標寸法を渡す。
# 幅と高さは4:2:0で扱える偶数へ丸める。
#
# RTX 5090の32GB VRAMで7B FP16を安定して動かすため、
# DiTの16ブロックとI/O部品をCPUへ退避し、VAEはタイル処理する。
# VRAMに余裕があればblocks_to_swapを減らすと高速になる。
#
# SeedVR2 CLIは動画を128フレームずつ処理し、チャンク境界へ時間的文脈を渡す。
# 出力はRGB48から10-bit RGB 4:4:4のx265 losslessへ逐次変換するため、全尺をRAMへ展開しない。
# gbrp10leはクロマサブサンプリングもRGB→YUV変換も行わないため、
# 10-bit量子化以降は数学的に無損失になる。
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
        (mkAppInputWith 8 "value" {
          description = "アスペクト比を維持した出力動画の長辺";
        })
      ];
      outputs = [
        15
        16
        5
      ];
    };
    nodes = [
      (mkNode {
        id = 1;
        type = "LoadVideo";
        title = "アップスケールする動画";
        pos = [
          (-40)
          190
        ];
        size = [
          340
          310
        ];
        order = 1;
        outputs = [
          (mkOutput "VIDEO" "VIDEO" [
            1
            26
          ])
        ];
        widgets = [
          "example.mp4"
          "image"
        ];
      })
      (mkNode {
        id = 2;
        type = "GetVideoSize";
        title = "元動画の解像度";
        pos = [
          360
          700
        ];
        size = [
          240
          100
        ];
        order = 2;
        inputs = [ (mkInput "video" "VIDEO" 1) ];
        outputs = [
          (mkOutput "width" "INT" [
            12
            14
          ])
          (mkOutput "height" "INT" [
            13
            15
          ])
        ];
      })
      (mkNode {
        id = 3;
        type = "SeedVR2LoadDiTModel";
        title = "SeedVR2 7B FP16";
        pos = [
          360
          40
        ];
        size = [
          390
          250
        ];
        order = 10;
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
          360
          330
        ];
        size = [
          390
          330
        ];
        order = 11;
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
        type = "SeedVR2StreamingVideoUpscaler";
        title = "時間的一貫性を保ってアップスケールして保存";
        pos = [
          780
          40
        ];
        size = [
          420
          520
        ];
        order = 12;
        inputs = [
          (mkInput "video" "VIDEO" 26)
          (mkInput "dit" "SEEDVR2_DIT" 3)
          (mkInput "vae" "SEEDVR2_VAE" 4)
          (
            mkInput "resolution" "INT" 20
            // {
              widget = {
                name = "resolution";
              };
            }
          )
          (
            mkInput "max_resolution" "INT" 21
            // {
              widget = {
                name = "max_resolution";
              };
            }
          )
          (
            mkInput "output_width" "INT" 16
            // {
              widget = {
                name = "output_width";
              };
            }
          )
          (
            mkInput "output_height" "INT" 17
            // {
              widget = {
                name = "output_height";
              };
            }
          )
        ];
        widgets = [
          42
          "fixed"
          2160 # resolution(計算した短辺から上書きされる)
          3840 # max_resolution(計算した長辺から上書きされる)
          3840 # output_width(元動画の比率から上書きされる)
          2160 # output_height(元動画の比率から上書きされる)
          5 # batch_size: 4n+1
          true # uniform_batch_size
          "lab" # color_correction
          3 # temporal_overlap
          0 # prepend_frames
          0 # input_noise_scale
          0 # latent_noise_scale
          "cpu" # offload_device
          128 # chunk_size
          (mkFilenamePrefix name) # filename_prefix
          1 # crf(losslessが偽の時のみ使用)
          true # lossless: x265 lossless RGB 4:4:4
          false # enable_debug
        ];
      })
      (mkNode {
        id = 8;
        type = "PrimitiveInt";
        title = "出力長辺(アスペクト比は自動維持)";
        pos = [
          (-40)
          40
        ];
        size = [
          315
          106
        ];
        order = 0;
        outputs = [
          (mkOutput "INT" "INT" [
            7
            11
          ])
        ];
        widgets = [
          3840 # value
          "fixed" # control_after_generate
        ];
      })
      (mkNode {
        id = 11;
        type = "ComfyMathExpression";
        title = "出力幅を自動計算";
        pos = [
          360
          840
        ];
        size = [
          315
          180
        ];
        order = 4;
        inputs = [
          (mkInput "values.a" "FLOAT,INT,BOOLEAN" 12)
          (mkInput "values.b" "FLOAT,INT,BOOLEAN" 13)
          (mkInput "values.c" "FLOAT,INT,BOOLEAN" 7)
          (
            mkInput "values.d" "FLOAT,INT,BOOLEAN" null
            // {
              shape = 7;
            }
          )
        ];
        outputs = [
          (mkOutput "FLOAT" "FLOAT" [ ])
          (mkOutput "INT" "INT" [
            16
            18
            22
            24
          ])
          (mkOutput "BOOL" "BOOLEAN" [ ])
        ];
        widgets = [ "round(a * c / max(a, b) / 2) * 2" ];
      })
      (mkNode {
        id = 12;
        type = "ComfyMathExpression";
        title = "出力高さを自動計算";
        pos = [
          360
          1060
        ];
        size = [
          315
          180
        ];
        order = 5;
        inputs = [
          (mkInput "values.a" "FLOAT,INT,BOOLEAN" 14)
          (mkInput "values.b" "FLOAT,INT,BOOLEAN" 15)
          (mkInput "values.c" "FLOAT,INT,BOOLEAN" 11)
          (
            mkInput "values.d" "FLOAT,INT,BOOLEAN" null
            // {
              shape = 7;
            }
          )
        ];
        outputs = [
          (mkOutput "FLOAT" "FLOAT" [ ])
          (mkOutput "INT" "INT" [
            17
            19
            23
            25
          ])
          (mkOutput "BOOL" "BOOLEAN" [ ])
        ];
        widgets = [ "round(b * c / max(a, b) / 2) * 2" ];
      })
      (mkNode {
        id = 13;
        type = "ComfyMathExpression";
        title = "SeedVR2の短辺を計算";
        pos = [
          690
          840
        ];
        size = [
          315
          130
        ];
        order = 8;
        inputs = [
          (mkInput "values.a" "FLOAT,INT,BOOLEAN" 22)
          (mkInput "values.b" "FLOAT,INT,BOOLEAN" 23)
        ];
        outputs = [
          (mkOutput "FLOAT" "FLOAT" [ ])
          (mkOutput "INT" "INT" [ 20 ])
          (mkOutput "BOOL" "BOOLEAN" [ ])
        ];
        widgets = [ "min(a, b)" ];
      })
      (mkNode {
        id = 14;
        type = "ComfyMathExpression";
        title = "SeedVR2の長辺上限を計算";
        pos = [
          690
          1060
        ];
        size = [
          315
          130
        ];
        order = 9;
        inputs = [
          (mkInput "values.a" "FLOAT,INT,BOOLEAN" 24)
          (mkInput "values.b" "FLOAT,INT,BOOLEAN" 25)
        ];
        outputs = [
          (mkOutput "FLOAT" "FLOAT" [ ])
          (mkOutput "INT" "INT" [ 21 ])
          (mkOutput "BOOL" "BOOLEAN" [ ])
        ];
        widgets = [ "max(a, b)" ];
      })
      # PreviewAnyは依存元の寸法計算が終わり次第UIへ結果を返す。
      # SeedVR2も同じ計算結果へ依存するため、重い推論の開始前に確認できる。
      (mkNode {
        id = 15;
        type = "PreviewAny";
        title = "自動計算された出力幅";
        pos = [
          1020
          840
        ];
        size = [
          315
          130
        ];
        order = 6;
        inputs = [ (mkInput "source" "*" 18) ];
        outputs = [ (mkOutput "STRING" "STRING" [ ]) ];
      })
      (mkNode {
        id = 16;
        type = "PreviewAny";
        title = "自動計算された出力高さ";
        pos = [
          1020
          1060
        ];
        size = [
          315
          130
        ];
        order = 7;
        inputs = [ (mkInput "source" "*" 19) ];
        outputs = [ (mkOutput "STRING" "STRING" [ ]) ];
      })
      (mkNode {
        id = 10;
        type = "Note";
        pos = [
          780
          610
        ];
        size = [
          555
          180
        ];
        order = 13;
        widgets = [
          "出力は映像のみのx265 10-bit RGB 4:4:4 lossless MP4。ハードウェアデコード非対応なのでmpvなどのソフトウェアデコードで再生する。元動画の映像以外を再muxする例:\n\nffmpeg -i upscaled.mp4 -i original.mkv -map 0:v:0 -map 1:a? -map 1:s? -map_metadata 1 -map_chapters 1 -c copy remuxed.mkv"
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
        26
        1
        0
        5
        0
        "VIDEO"
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
        7
        8
        0
        11
        2
        "INT"
      ]
      [
        11
        8
        0
        12
        2
        "INT"
      ]
      [
        12
        2
        0
        11
        0
        "INT"
      ]
      [
        13
        2
        1
        11
        1
        "INT"
      ]
      [
        14
        2
        0
        12
        0
        "INT"
      ]
      [
        15
        2
        1
        12
        1
        "INT"
      ]
      [
        16
        11
        1
        5
        5
        "INT"
      ]
      [
        17
        12
        1
        5
        6
        "INT"
      ]
      [
        18
        11
        1
        15
        0
        "INT"
      ]
      [
        19
        12
        1
        16
        0
        "INT"
      ]
      [
        20
        13
        1
        5
        3
        "INT"
      ]
      [
        21
        14
        1
        5
        4
        "INT"
      ]
      [
        22
        11
        1
        13
        0
        "INT"
      ]
      [
        23
        12
        1
        13
        1
        "INT"
      ]
      [
        24
        11
        1
        14
        0
        "INT"
      ]
      [
        25
        12
        1
        14
        1
        "INT"
      ]
    ];
  };
}
