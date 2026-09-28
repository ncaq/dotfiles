# Open WebUIの画像編集をbulletのComfyUIで行う。
#
# ワークフローはbulletの`qwen-edit`をAPI形式へ書き写したものである。
# 書き写しの経緯と二重管理についての注意は`image-generation.nix`に書いてある。
# ComfyUIへの経路は`comfyui-backend.nix`の中継を画像生成と共有する。
#
# Qwen-Image-2.1は参照画像を渡すと指示ベースの編集になり、
# 「テーブルの上の物を消して」のような自然言語の指示で元画像の同一性を保ったまま変更する。
# 画像全体を描き直す`anima-edit`や`sdxl-edit`のimg2imgとは性質が違う。
# チャットから画像を渡して指示を書く、というOpen WebUIの操作に合うのはこちらである。
#
# 指示文をリライトする`RewriteEditPrompt`はbulletの定義のまま残す。
#
# Open WebUIにも`ENABLE_IMAGE_PROMPT_GENERATION`があるが、代わりにはならない。
# あちらの`image_prompt_generation_template`はmessagesから組み立てるので、
# 見るのはテキストの会話履歴だけで画像そのものは見ない。
# `RewriteEditPrompt`は画像ごとQwen-Image-2.1公式のPE-I2Iへ渡すため、
# 「髪をポニーテールにして」から、
# 「元はツーサイドアップで、服装は変えずに」といった具体化ができる。
# PE-I2IはQwen-Image-2.1が前提とする指示文の書式と、
# 出力のキャンバスの比率の決め方まで学習している。
# チャットのモデルに書かせてこの規則を守らせる手段は用意されていない。
#
# 末尾の`FreeVram`のノード`21`はbulletの`qwen-edit`には無い意図的な差分で、
# 生成が終わった後に次のOllamaのために空けておくためのものである。
# 同期する時に写し漏れと誤解して消さないこと。
{ lib, config, ... }:
let
  # 参照画像と出力を揃える解像度はbulletの定義をそのまま引く。
  # 理由は`image-generation.nix`が寸法の整列単位を引いているのと同じである。
  inherit (import ../../bullet/comfyui/workflow/lib/builder.nix { inherit lib; })
    qwenImageEditResolution
    ;

  model = "qwen_image_2.1_int8_convrot.safetensors";

  workflow = {
    "1" = {
      class_type = "UNETLoader";
      inputs = {
        unet_name = model;
        weight_dtype = "default";
      };
    };
    "16" = {
      class_type = "Lora Loader (LoraManager)";
      inputs = {
        model = [
          "1"
          0
        ];
        text = "";
      };
    };
    "2" = {
      class_type = "CLIPLoader";
      inputs = {
        clip_name = "qwen3vl_8b_bf16.safetensors";
        type = "qwen_image";
        device = "default";
      };
    };
    "19" = {
      class_type = "CLIPLoader";
      inputs = {
        clip_name = "qwen3.5_9b_qwen_image_2.1_pe_i2i.int8_convrot.safetensors";
        type = "qwen_image";
        device = "default";
      };
    };
    "3" = {
      class_type = "VAELoader";
      inputs.vae_name = "qwen_image_2.1_vae_bf16.safetensors";
    };
    # 編集の対象。
    # Open WebUIがComfyUIの`/api/upload/image`へ上げた後のファイル名で差し替わる。
    "4" = {
      class_type = "LoadImage";
      inputs.image = "example.png";
    };
    # 2枚目以降の参照画像。
    # Open WebUIが渡した枚数だけ順に埋まり、残りは`(none)`のままになる。
    "17" = {
      class_type = "LoadImageOptional";
      inputs.image = "(none)";
    };
    "18" = {
      class_type = "LoadImageOptional";
      inputs.image = "(none)";
    };
    # 指示文を画像ごとPE-I2Iへ渡して、Qwen-Image-2.1が前提とする形式へ書き直す。
    # 出力のキャンバスの幅と高さもここで決まる。
    "14" = {
      class_type = "RewriteEditPrompt";
      inputs = {
        text = "";
        seed = 0;
        resolution = qwenImageEditResolution;
        clip = [
          "19"
          0
        ];
        image1 = [
          "4"
          0
        ];
        image2 = [
          "17"
          0
        ];
        image3 = [
          "18"
          0
        ];
      };
    };
    # 書き直した後の指示文をComfyUIのUIから確認するためのノード。
    # 画像ではないのでOpen WebUIは出力として拾わない。
    "15" = {
      class_type = "PreviewAny";
      inputs.source = [
        "14"
        0
      ];
    };
    # 参照画像の入力は数が増えていく入力なので、
    # API形式では`images.image_1`のようにグループ名で修飾した名前で渡す。
    "6" = {
      class_type = "TextEncodeQwenImage21";
      inputs = {
        prompt = [
          "14"
          0
        ];
        negative_prompt = "";
        resolution = qwenImageEditResolution;
        clip = [
          "2"
          0
        ];
        vae = [
          "3"
          0
        ];
        "images.image_1" = [
          "4"
          0
        ];
        "images.image_2" = [
          "17"
          0
        ];
        "images.image_3" = [
          "18"
          0
        ];
      };
    };
    "20" = {
      class_type = "EmptyLatentImage";
      inputs = {
        width = [
          "14"
          1
        ];
        height = [
          "14"
          2
        ];
        batch_size = 1;
      };
    };
    "11" = {
      class_type = "KSampler";
      inputs = {
        seed = 0;
        steps = 40;
        cfg = 1;
        sampler_name = "euler";
        scheduler = "simple";
        denoise = 1;
        model = [
          "16"
          0
        ];
        positive = [
          "6"
          0
        ];
        negative = [
          "6"
          1
        ];
        latent_image = [
          "20"
          0
        ];
      };
    };
    "12" = {
      class_type = "VAEDecode";
      inputs = {
        samples = [
          "11"
          0
        ];
        vae = [
          "3"
          0
        ];
      };
    };
    # 編集が終わったのでComfyUIの重みをVRAMから降ろす。
    # 理由と挟む位置については`image-generation.nix`に書いてある。
    "21" = {
      class_type = "FreeVram";
      inputs = {
        enabled = true;
        image = [
          "12"
          0
        ];
      };
    };
    # `%`の二重化については`image-generation.nix`に理由を書いてある。
    "13" = {
      class_type = "SaveImage";
      inputs = {
        filename_prefix = "open-webui-edit/open-webui-edit-%%year%%-%%month%%-%%day%%-%%hour%%-%%minute%%-%%second%%";
        images = [
          "21"
          0
        ];
      };
    };
  };

  # 画像は渡された枚数だけ順に埋まる。
  # 1枚なら`4`だけが差し替わり、`17`と`18`は`(none)`のまま残る。
  #
  # negative promptは渡さない。
  # `ComfyUIEditImageForm`は画像生成の側と違って`negative_prompt`を持たないため、
  # そのtypeを書くと`_apply_workflow_nodes`が存在しない属性を読んで実行時に落ちる。
  # ノード`6`のnegative_promptは空のままにする。
  #
  # stepsも渡さない。
  # フィールド自体はあるが既定が`None`で、
  # 画像生成の`IMAGE_STEPS`にあたる設定が編集の側には無いため誰も値を入れない。
  # そのまま流すとKSamplerが`steps`を`None`で受け取り、
  # `SaveImage`へ至る経路だけがバリデーションで落ちる。
  # `PreviewAny`はKSamplerを通らないので生き残り、
  # 全体は`success`のまま画像が返らないという分かりにくい壊れ方をする。
  # ワークフロー側の40をそのまま使う。
  #
  # seedは渡してよい。
  # `_apply_workflow_nodes`が`None`の時に乱数へ倒す分岐を持っている。
  # 渡すのは生成のKSamplerだけで、書き換えのseedは固定のままにする。
  #
  # 寸法は指定しない。
  # 出力の寸法は`RewriteEditPrompt`が指示と入力画像から決めるため、
  # UIから渡された値で上書きすると元画像との対応が崩れる。
  workflowNodes = [
    {
      type = "model";
      key = "unet_name";
      node_ids = [ "1" ];
    }
    {
      type = "prompt";
      key = "text";
      node_ids = [ "14" ];
    }
    {
      type = "image";
      key = "image";
      node_ids = [
        "4"
        "17"
        "18"
      ];
    }
    {
      type = "seed";
      key = "seed";
      node_ids = [ "11" ];
    }
  ];
in
{
  # 手で書き写した接続とUIの入力の対応を評価時に検査する。
  # 画像生成と共有する定義で、検査の内容はそちらに書いてある。
  #
  # `validTypes`は生成の側と包含関係にない。
  # `negative_prompt`と`width`/`height`/`steps`を含まないのは、
  # `ComfyUIEditImageForm`が前者の属性を持たず、
  # 後者には値を入れる設定が無いためである。
  # 代わりに生成の側に無い`image`を持つ。
  # それぞれの理由は`workflowNodes`の直前に書いてある。
  assertions = (import ../../../../lib/comfyui-api-workflow.nix { inherit lib; }).assertions {
    name = "Open WebUIの画像編集";
    inherit workflow workflowNodes;
    validTypes = [
      "model"
      "prompt"
      "image"
      "seed"
    ];
    requiredTypes = [
      "model"
      "prompt"
      "image"
    ];
  };

  local.openWebui.environment = {
    ENABLE_IMAGE_EDIT = "True";
    IMAGE_EDIT_ENGINE = "comfyui";
    IMAGE_EDIT_MODEL = model;

    # 転送先は`comfyui-backend.nix`が立てたCaddyで、画像生成と共有する。
    IMAGES_EDIT_COMFYUI_BASE_URL = config.local.openWebui.comfyuiUrl;
    IMAGES_EDIT_COMFYUI_WORKFLOW = builtins.toJSON workflow;
    IMAGES_EDIT_COMFYUI_WORKFLOW_NODES = builtins.toJSON workflowNodes;
  };
}
