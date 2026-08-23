# Open WebUIの画像生成をbulletのComfyUIで行う。
#
# ワークフローはbulletの`anima-standard`をAPI形式へ書き写したものである。
# ComfyUIのワークフローにはUI形式とAPI形式があり、
# 前者は`widgets_values`が配列で並び順だけがフィールドを表すのに対し、
# 後者は`inputs`へ名前付きで書いて接続を`[ノードID, 出力スロット]`で埋め込む。
# 変換はブラウザ上のフロントエンドが行うため、
# `bullet/comfyui/workflow`の定義をそのまま渡すことはできない。
#
# 書き写しにあたっては`/object_info`が返すノード定義の`input_order`を使い、
# ウィジェットになる入力の順序に`widgets_values`を機械的に対応させた。
# 手で並べ替えると`FaceDetailer`の28個のような列で必ず間違える。
#
# 二重管理になるのは承知の上である。
# 1つの定義から両方の形式を導くには、
# 全ノードのウィジェット名をNixの側へ持つ必要があり、
# 実際に画像生成を使うかどうかも分からない段階で払う設計コストとしては重い。
# bullet側の`anima-standard`を変更した場合は、ここも追随させること。
{ config, ... }:
let
  addr = config.machineAddresses.open-webui;
  port = config.local.openWebui.comfyuiPort;

  # `bullet/comfyui/workflow/lib/builder.nix`と同じ値を使う。
  # あちらを変えた時に気付けるよう、由来の分かる名前で束縛しておく。
  model = "anima-aesthetic-v1.1.safetensors";
  sizeMultiple = 16;
  baseSteps = 30;
  hiresDenoise = 0.3;
  faceDenoise = 0.35;
  # `stepsForDenoise`と同じ計算。
  # KSamplerはdenoiseを下げてもstepsの回数だけサンプリングするため、
  # sigmaの刻み密度を素の生成へ揃えるには`基準のsteps * denoise`にする。
  hiresSteps = 9;
  faceSteps = 10;

  # Open WebUIが上書きするので初期値そのものは使われないが、
  # ワークフロー単体をComfyUIへ投げた時にも成立する内容にしておく。
  # `1girl`のような題材の決め打ちは、汎用の入口としては邪魔なので入れない。
  positivePrompt = "masterpiece, best quality";
  negativePrompt = "worst quality, low quality, artist name, blurry, jpeg artifacts, chromatic aberration";

  workflow = {
    "1" = {
      class_type = "UNETLoader";
      inputs = {
        unet_name = model;
        weight_dtype = "default";
      };
    };
    "2" = {
      class_type = "CLIPLoader";
      inputs = {
        clip_name = "qwen_3_06b_base.safetensors";
        type = "stable_diffusion";
        device = "default";
      };
    };
    "3" = {
      class_type = "VAELoader";
      inputs.vae_name = "qwen_image_vae.safetensors";
    };
    # Anima公式はLLM adapterを学習しないよう推奨しているため、
    # LoRAはMODELだけへ適用してCLIPを素通しする。
    # `text`はLoRAの指定で、空なら何も適用しない。
    "10" = {
      class_type = "Lora Loader (LoraManager)";
      inputs = {
        model = [
          "1"
          0
        ];
        text = "";
      };
    };
    "4" = {
      class_type = "CLIPTextEncode";
      inputs = {
        text = positivePrompt;
        clip = [
          "2"
          0
        ];
      };
    };
    "5" = {
      class_type = "CLIPTextEncode";
      inputs = {
        text = negativePrompt;
        clip = [
          "2"
          0
        ];
      };
    };
    # Open WebUIから来る寸法をAnimaが要求する16の倍数へ切り下げる。
    "20" = {
      class_type = "AlignImageDimensions";
      inputs = {
        width = 1024;
        height = 1024;
        multiple = sizeMultiple;
      };
    };
    "6" = {
      class_type = "EmptyLatentImage";
      inputs = {
        width = [
          "20"
          0
        ];
        height = [
          "20"
          1
        ];
        batch_size = 1;
      };
    };
    "9" = {
      class_type = "UpscaleModelLoader";
      inputs.model_name = "2x-AnimeSharpV4_Fast_RCAN_PU.safetensors";
    };
    "16" = {
      class_type = "UltralyticsDetectorProvider";
      inputs.model_name = "bbox/face_yolov9c.pt";
    };
    "7" = {
      class_type = "KSampler";
      inputs = {
        seed = 0;
        steps = baseSteps;
        cfg = 4;
        sampler_name = "euler";
        scheduler = "simple";
        denoise = 1;
        model = [
          "10"
          0
        ];
        positive = [
          "4"
          0
        ];
        negative = [
          "5"
          0
        ];
        latent_image = [
          "6"
          0
        ];
      };
    };
    "8" = {
      class_type = "VAEDecode";
      inputs = {
        samples = [
          "7"
          0
        ];
        vae = [
          "3"
          0
        ];
      };
    };
    "11" = {
      class_type = "ImageUpscaleWithModel";
      inputs = {
        upscale_model = [
          "9"
          0
        ];
        image = [
          "8"
          0
        ];
      };
    };
    # 2倍アップスケール後に0.75倍へ縮小し、全体で1.5倍にする。
    # 縮小を挟むのはスーパーサンプリングになってエッジが整うため。
    "12" = {
      class_type = "ImageScaleBy";
      inputs = {
        upscale_method = "area";
        scale_by = 0.75;
        image = [
          "11"
          0
        ];
      };
    };
    "19" = {
      class_type = "AlignImageSize";
      inputs = {
        multiple = sizeMultiple;
        image = [
          "12"
          0
        ];
      };
    };
    "13" = {
      class_type = "VAEEncode";
      inputs = {
        pixels = [
          "19"
          0
        ];
        vae = [
          "3"
          0
        ];
      };
    };
    # 元の構図と顔を維持しながらアップスケーラの細部だけを再生成する。
    "14" = {
      class_type = "KSampler";
      inputs = {
        seed = 0;
        steps = hiresSteps;
        cfg = 4;
        sampler_name = "euler";
        scheduler = "simple";
        denoise = hiresDenoise;
        model = [
          "10"
          0
        ];
        positive = [
          "4"
          0
        ];
        negative = [
          "5"
          0
        ];
        latent_image = [
          "13"
          0
        ];
      };
    };
    "15" = {
      class_type = "VAEDecode";
      inputs = {
        samples = [
          "14"
          0
        ];
        vae = [
          "3"
          0
        ];
      };
    };
    "17" = {
      class_type = "FaceDetailer";
      inputs = {
        guide_size = 512;
        guide_size_for = true;
        max_size = 1024;
        seed = 0;
        steps = faceSteps;
        cfg = 4;
        sampler_name = "euler";
        scheduler = "simple";
        denoise = faceDenoise;
        feather = 5;
        noise_mask = true;
        force_inpaint = true;
        bbox_threshold = 0.5;
        bbox_dilation = 10;
        bbox_crop_factor = 3.0;
        sam_detection_hint = "center-1";
        sam_dilation = 0;
        sam_threshold = 0.93;
        sam_bbox_expansion = 0;
        sam_mask_hint_threshold = 0.7;
        sam_mask_hint_use_negative = "False";
        drop_size = 32;
        wildcard = "";
        cycle = 1;
        inpaint_model = false;
        noise_mask_feather = 20;
        tiled_encode = false;
        tiled_decode = false;
        image = [
          "15"
          0
        ];
        model = [
          "10"
          0
        ];
        clip = [
          "2"
          0
        ];
        vae = [
          "3"
          0
        ];
        positive = [
          "4"
          0
        ];
        negative = [
          "5"
          0
        ];
        bbox_detector = [
          "16"
          0
        ];
      };
    };
    # Open WebUIは`SaveImage`か`PreviewImage`の出力だけを画像として拾う。
    #
    # `%`を二重にするのはsystemdのspecifierから守るためである。
    # ワークフローは環境変数としてユニットの`Environment=`に載るので、
    # `%year%`をそのまま書くと`%y`がユニットファイルのパスへ、
    # `%month%`の`%m`がマシンIDへ、
    # `%second%`の`%s`がシェルのパスへ展開されて名前が壊れる。
    # bulletはワークフローをJSONファイルとして配置するのでこの問題を踏まない。
    "18" = {
      class_type = "SaveImage";
      inputs = {
        filename_prefix = "open-webui/open-webui-%%year%%-%%month%%-%%day%%-%%hour%%-%%minute%%-%%second%%";
        images = [
          "17"
          0
        ];
      };
    };
  };

  # UIの入力をワークフローのどのノードへ流し込むかの対応。
  #
  # seedは3つのサンプラーへ同じ値を配る。
  # UI形式では各ノードが独立してランダム化されるが、
  # API形式には実行ごとに振り直す仕組みが無いので、
  # ここで配らないと毎回同じノイズから生成することになる。
  #
  # stepsは素の生成にだけ渡す。
  # hires fixとFaceDetailerのstepsはdenoiseから逆算した固定値で、
  # 刻み密度を素の生成へ揃えるためのものなので、
  # UIから来た値をそのまま入れると意味が変わる。
  workflowNodes = [
    {
      type = "model";
      key = "unet_name";
      node_ids = [ "1" ];
    }
    {
      type = "prompt";
      key = "text";
      node_ids = [ "4" ];
    }
    {
      type = "negative_prompt";
      key = "text";
      node_ids = [ "5" ];
    }
    {
      type = "width";
      key = "width";
      node_ids = [ "20" ];
    }
    {
      type = "height";
      key = "height";
      node_ids = [ "20" ];
    }
    {
      type = "steps";
      key = "steps";
      node_ids = [ "7" ];
    }
    {
      type = "seed";
      key = "seed";
      node_ids = [
        "7"
        "14"
        "17"
      ];
    }
  ];
in
{
  local.openWebui.environment = {
    ENABLE_IMAGE_GENERATION = "True";
    IMAGE_GENERATION_ENGINE = "comfyui";
    COMFYUI_BASE_URL = "http://${addr.host}:${toString port}";
    COMFYUI_WORKFLOW = builtins.toJSON workflow;
    COMFYUI_WORKFLOW_NODES = builtins.toJSON workflowNodes;

    IMAGE_GENERATION_MODEL = model;
    # 既定の`512x512`はAnimaの学習解像度から外れる。
    IMAGE_SIZE = "1024x1024";
    # 既定の50はこのワークフローには過剰である。
    IMAGE_STEPS = toString baseSteps;
  };
}
