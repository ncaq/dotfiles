# Open WebUIの画像編集をbulletのComfyUIで行う。
#
# ワークフローはbulletの`qwen-edit`をAPI形式へ書き写したものである。
# 書き写しの経緯と二重管理についての注意は`image-generation.nix`に書いてある。
# ComfyUIへの経路は`comfyui-backend.nix`の中継を画像生成と共有する。
#
# Qwen-Image-Edit 2511は指示ベースの編集で、
# 「テーブルの上の物を消して」のような自然言語の指示で元画像の同一性を保ったまま変更する。
# 画像全体を描き直す`anima-edit`や`sdxl-edit`のimg2imgとは性質が違う。
# チャットから画像を渡して指示を書く、というOpen WebUIの操作に合うのはこちらである。
#
# 指示文をリライトする`RewriteEditPrompt`はbulletの定義のまま残す。
#
# Open WebUIにも`ENABLE_IMAGE_PROMPT_GENERATION`があるが、代わりにはならない。
# あちらの`image_prompt_generation_template`はmessagesから組み立てるので、
# 見るのはテキストの会話履歴だけで画像そのものは見ない。
# `RewriteEditPrompt`は`QwenImageEditScale`の出力を受け取ってVLMへ画像を見せるため、
# 「髪をポニーテールにして」から、
# 「元はツーサイドアップで、服装は変えずに」といった具体化ができる。
#
# システムプロンプトもQwen-Image公式の`EDIT_SYSTEM_PROMPT`をそのまま使っていて、
# テキスト編集は英語の二重引用符で囲むとか、
# colorizationは固定の文へ倒すといった、
# Qwen-Image-Editが前提とする形式への正規化まで含んでいる。
# チャットのモデルに書かせてこの規則を守らせる手段は用意されていない。
#
# 代償は`free_comfyui_vram`によるVRAMの往復である。
# リライトのたびに編集モデルを退かしてOllamaを読み、
# 書き直してから編集モデルを読み直すことになる。
# 速度が要るほど使うなら直接ComfyUIを開けばよい、という判断で正確さを取る。
{ lib, config, ... }:
let
  model = "qwen_image_edit_2511_int8_convrot.safetensors";

  # 指示文のリライトを担う`RewriteEditPrompt`へ渡すOllamaのモデル名。
  #
  # ComfyUIが動くのはbulletなので、
  # seminar自身の`hostModels`ではなくCUDAのホストの表から引く。
  # 接続先のハードウェアでモデルが決まる関係は`blue-prompt.nix`と同じである。
  #
  # assertionではなく`throw`にするのは、
  # `option.nix`の`%`の検査が`environment`の全ての値を強制評価するためである。
  # そちらの評価はassertionの並び順と関係なく走るので、
  # 空リストなら`lib.head`が先に`head: empty list`を投げて、
  # 用意したメッセージは決して表示されない。
  # 値そのものが理由を語る形にすれば、どの経路から評価されても同じ文章が出る。
  rewriteModel =
    let
      generalModels = config.local.ollama.models.cuda.general;
    in
    if generalModels == [ ] then
      throw "Open WebUIの画像編集は指示文のリライトにOllamaの汎用モデルを使うため、local.ollama.models.cuda.generalが空であってはなりません。"
    else
      lib.head generalModels;

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
        clip_name = "qwen_2.5_vl_7b.safetensors";
        type = "qwen_image";
        device = "default";
      };
    };
    "3" = {
      class_type = "VAELoader";
      inputs.vae_name = "qwen_image_vae.safetensors";
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
    # Qwen-Image-Editが前提とする画素数と整列単位へ入力画像を合わせる。
    "5" = {
      class_type = "QwenImageEditScale";
      inputs.image = [
        "4"
        0
      ];
    };
    # 指示文を画像ごとOllamaへ渡して、Qwen-Image-Editが前提とする形式へ書き直す。
    # モデル名の由来は`rewriteModel`の束縛に書いてある。
    "14" = {
      class_type = "RewriteEditPrompt";
      inputs = {
        text = "";
        model = rewriteModel;
        free_comfyui_vram = true;
        image = [
          "5"
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
    "6" = {
      class_type = "TextEncodeQwenImageEditPlus";
      inputs = {
        prompt = [
          "14"
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
        image1 = [
          "5"
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
    "7" = {
      class_type = "TextEncodeQwenImageEditPlus";
      inputs = {
        prompt = "";
        clip = [
          "2"
          0
        ];
        vae = [
          "3"
          0
        ];
        image1 = [
          "5"
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
    "8" = {
      class_type = "ModelSamplingAuraFlow";
      inputs = {
        shift = 3.1;
        model = [
          "16"
          0
        ];
      };
    };
    "9" = {
      class_type = "CFGNorm";
      inputs = {
        strength = 1;
        pre_cfg = false;
        model = [
          "8"
          0
        ];
      };
    };
    "10" = {
      class_type = "VAEEncode";
      inputs = {
        pixels = [
          "5"
          0
        ];
        vae = [
          "3"
          0
        ];
      };
    };
    "11" = {
      class_type = "KSampler";
      inputs = {
        seed = 0;
        steps = 40;
        cfg = 4;
        sampler_name = "euler";
        scheduler = "simple";
        denoise = 1;
        model = [
          "9"
          0
        ];
        positive = [
          "6"
          0
        ];
        negative = [
          "7"
          0
        ];
        latent_image = [
          "10"
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
    #
    # このワークフローは`RewriteEditPrompt`が`free_comfyui_vram`で一度降ろすが、
    # あちらはリライトのためにOllamaを呼ぶ直前の話で、
    # その後の編集で重みは載り直す。
    "19" = {
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
          "19"
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
  # ノード`7`のpromptは空のままにする。
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
  #
  # 寸法は指定しない。
  # `QwenImageEditScale`が入力画像から必要な画素数と整列単位へ合わせるため、
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
  # `validTypes`が生成の側より狭いのは、
  # `ComfyUIEditImageForm`が`negative_prompt`を持たず、
  # `steps`と寸法には値を入れる設定が無いためである。
  # 理由は`workflowNodes`の直前に書いてある。
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
