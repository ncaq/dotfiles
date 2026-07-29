# ComfyUIの`models/`配下に宣言的に配置するモデルファイル群。
#
# モデルはNix storeへfetchurlで取得して、
# ComfyUIのmodelsディレクトリへシンボリックリンクで配置する。
# storeのパスはホストのシステムクロージャから参照されるのでGCされない。
# コンテナはephemeralだがホスト側のtmpfilesルールなので再起動しても残る。
#
# CivitAIのダウンロードURLはAPIキーが必要なことがあるため、
# 認証なしで安定して取得できるHugging FaceのURLのみを使う。
# リポジトリの更新でハッシュがずれないように、
# URLは`resolve/main`ではなくcommit hashで固定する。
{
  lib,
  pkgs,
  config,
  ...
}:
let
  dataDir = config.containers.comfyui.config.services.comfyui.dataDir;
  # Hugging Faceからモデルファイルを取得するヘルパー。
  # revにはリポジトリのcommit hashを指定する。
  fetchHuggingface =
    {
      owner,
      repo,
      rev,
      file,
      hash,
    }:
    pkgs.fetchurl {
      url = "https://huggingface.co/${owner}/${repo}/resolve/${rev}/${file}";
      inherit hash;
    };
  # 属性名は`models/`配下のディレクトリ名、
  # その中の属性名が配置するファイル名に対応する。
  models = {
    checkpoints = {
      # Illustrious-XLベースの人気マージモデル。日常使いの定番。
      # CivitAIオリジナルの非公式ミラーなので消失リスクがある。
      "waiIllustriousSDXL_v170.safetensors" = fetchHuggingface {
        owner = "LyliaEngine";
        repo = "waiIllustriousSDXL_v170";
        rev = "5ef4e2da7173a160ad04aebcaa2fdcd6d20ed792";
        file = "waiIllustriousSDXL_v170.safetensors";
        hash = "sha256-8Rawx4/0QUZ7DNyPGTbh7RjqMemZfHsTKxuNtTPwvQQ=";
      };
      # SDXLをアニメ画像で再学習したモデル。タグ設計が分かりやすい。
      "animagine-xl-4.0.safetensors" = fetchHuggingface {
        owner = "cagliostrolab";
        repo = "animagine-xl-4.0";
        rev = "2b7c1b397761bf5bd3cc42e5b39ec99314a75a96";
        file = "animagine-xl-4.0.safetensors";
        hash = "sha256-HVtD/3W2q1mFAtTHedL7+j3OylHGDDtglkCmB3IzORY=";
      };
    };
    # UNETLoaderが読むcheckpoint非統合の拡散モデル。
    diffusion_models = {
      # 指示文で画像を編集するQwen-Image-Editの2025年11月版。
      # Comfy-Org公式の再パッケージ版。Apache 2.0ライセンス。
      "qwen_image_edit_2511_fp8mixed.safetensors" = fetchHuggingface {
        owner = "Comfy-Org";
        repo = "Qwen-Image-Edit_ComfyUI";
        rev = "e9e85de74a8f48c1e3e2656617626348675a2f21";
        file = "split_files/diffusion_models/qwen_image_edit_2511_fp8mixed.safetensors";
        hash = "sha256-yf3BWORtO2HvdfIa6GbKL+gIv0pTZDEg0cHofBkoCk4=";
      };
      # Wan 2.2 I2V 14B MoEを4ステップ用に蒸留したfull expertモデル2つ。
      # LoRA近似ではなく蒸留済みの全重みを使い、
      # サンプリング前半をhigh noise、後半をlow noiseが担当する。
      # Apache 2.0ライセンス。
      "wan2.2_i2v_A14b_high_noise_lightx2v_4step.safetensors" = fetchHuggingface {
        owner = "lightx2v";
        repo = "Wan2.2-Distill-Models";
        rev = "715f592b12e99e398923d255ee6a4dae85543cee";
        file = "wan2.2_i2v_A14b_high_noise_lightx2v_4step.safetensors";
        hash = "sha256-OdOvdORuWemJ21zDb0AeZm8653x2SOtV06/5/uR3Fvo=";
      };
      "wan2.2_i2v_A14b_low_noise_lightx2v_4step.safetensors" = fetchHuggingface {
        owner = "lightx2v";
        repo = "Wan2.2-Distill-Models";
        rev = "715f592b12e99e398923d255ee6a4dae85543cee";
        file = "wan2.2_i2v_A14b_low_noise_lightx2v_4step.safetensors";
        hash = "sha256-o7hoCv/iqy4hISEKg/+n01H3faGBkeV7s1nXg5vrqKI=";
      };
    };
    text_encoders = {
      # Qwen-Image-Editで編集指示と入力画像を解析するVLM。
      # 画像理解と複雑な指示の精度を優先してBF16版を使う。
      "qwen_2.5_vl_7b.safetensors" = fetchHuggingface {
        owner = "Comfy-Org";
        repo = "Qwen-Image_ComfyUI";
        rev = "46839d338df81ce625d5fae27d7e370314c0fbc9";
        file = "split_files/text_encoders/qwen_2.5_vl_7b.safetensors";
        hash = "sha256-z6/XOUWbyGJXOXJZ9hKpruiOW5joW1wNDRcX6JizRjo=";
      };
      # Wan系が使うテキストエンコーダ。
      # 複雑な動作やカメラ指示の追従精度を優先してFP16版を使う。
      "umt5_xxl_fp16.safetensors" = fetchHuggingface {
        owner = "Comfy-Org";
        repo = "Wan_2.2_ComfyUI_Repackaged";
        rev = "fb1388adc906ab39ffc26ee40e96b22886b56bc4";
        file = "split_files/text_encoders/umt5_xxl_fp16.safetensors";
        hash = "sha256-e4hQ8ZYeHPinfMpMlko1jTA/SQgzxsCH0M/0svmdsq8=";
      };
    };
    vae = {
      # Qwen-Image系のVAE。
      "qwen_image_vae.safetensors" = fetchHuggingface {
        owner = "Comfy-Org";
        repo = "Qwen-Image_ComfyUI";
        rev = "46839d338df81ce625d5fae27d7e370314c0fbc9";
        file = "split_files/vae/qwen_image_vae.safetensors";
        hash = "sha256-pwWA8CE+Z5Z+6clfBbtADo+wgwfgF6kkvzRBIj4CPR8=";
      };
      # Wan 2.2 14BはWan 2.1と共通のVAEを使う。
      "wan_2.1_vae.safetensors" = fetchHuggingface {
        owner = "Comfy-Org";
        repo = "Wan_2.2_ComfyUI_Repackaged";
        rev = "fb1388adc906ab39ffc26ee40e96b22886b56bc4";
        file = "split_files/vae/wan_2.1_vae.safetensors";
        hash = "sha256-L8OdMTWaSwpk9Vh22P9/qNeAlWriyxNGOwIj4VFIl2s=";
      };
    };
    controlnet = {
      # SDXL系全般で使えるControlNet統合モデル(ProMax版)。
      # openpose/lineart/tileなど複数のコントロールをこれ1つで扱える。
      "controlnet-union-sdxl-promax.safetensors" = fetchHuggingface {
        owner = "xinsir";
        repo = "controlnet-union-sdxl-1.0";
        rev = "801a4a3fa3d4c936f4feea95b98607bc6726f80c";
        file = "diffusion_pytorch_model_promax.safetensors";
        hash = "sha256-n64uUMtDG/y+BYIrWewiKN9UXvJ/cR3qiUnp9O2ffNw=";
      };
    };
    # Impact SubpackのUltralyticsDetectorProviderが読む検出モデル。
    "ultralytics/bbox" = {
      # FaceDetailerでの顔検出に使うYOLOモデル。
      "face_yolov8m.pt" = fetchHuggingface {
        owner = "Bingsu";
        repo = "adetailer";
        rev = "53cc19de382014514d9d4038601d261a7faa9b7b";
        file = "face_yolov8m.pt";
        hash = "sha256-cXkjwZs/S79SULco8fprLLcqM67R0jbqnK8OIa2UPl8=";
      };
    };
    upscale_models = {
      # アニメ絵向けの定番アップスケーラ。
      "4x-AnimeSharp.safetensors" = fetchHuggingface {
        owner = "Kim2091";
        repo = "AnimeSharp";
        rev = "7696d95ced82b0c1f2a41f6ac73336133f0a90e1";
        file = "4x-AnimeSharp.safetensors";
        hash = "sha256-f8YAVNKRV5rKxPtTfv2RyAYRy9KB74uQ9DQEjMExOzk=";
      };
      # Real-ESRGANのアニメ特化軽量版。
      "RealESRGAN_x4plus_anime_6B.pth" = pkgs.fetchurl {
        url = "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth";
        hash = "sha256-+HLYN9PJDtLgUie+1xGvVnGm/RyffX6RyRGmHxVemdo=";
      };
    };
    # ComfyUI-SeedVR2_VideoUpscalerが登録する専用モデルディレクトリ。
    # 通常版はsharp版より線の過剰強調が少ないため、アニメ動画の標準にする。
    SEEDVR2 = {
      "seedvr2_ema_7b_fp16.safetensors" = fetchHuggingface {
        owner = "numz";
        repo = "SeedVR2_comfyUI";
        rev = "09ced71023636e9bc8cdf9cdecfb2625d1e691e8";
        file = "seedvr2_ema_7b_fp16.safetensors";
        hash = "sha256-e4JBqpV2Bqts+2btq8ltQyNPmBnFOStE0kktnwsLvko=";
      };
      "ema_vae_fp16.safetensors" = fetchHuggingface {
        owner = "numz";
        repo = "SeedVR2_comfyUI";
        rev = "09ced71023636e9bc8cdf9cdecfb2625d1e691e8";
        file = "ema_vae_fp16.safetensors";
        hash = "sha256-IGeFSPQg2Y0m8RRC01KPi4yU5X7gRu+T27djPahhLKE=";
      };
    };
  };
  # カテゴリ名(ultralytics/bboxのような入れ子含む)から、
  # 作成するべきディレクトリの前置パス一覧を求める。
  modelDirs = lib.unique (
    lib.concatMap (
      category:
      let
        parts = lib.splitString "/" category;
      in
      lib.genList (i: lib.concatStringsSep "/" (lib.take (i + 1) parts)) (lib.length parts)
    ) (lib.attrNames models)
  );
  modelDirRules = map (dir: "d ${dataDir}/models/${dir} 0755 comfyui comfyui - -") modelDirs;
  modelLinkRules = lib.flatten (
    lib.mapAttrsToList (
      category:
      lib.mapAttrsToList (name: file: "L+ ${dataDir}/models/${category}/${name} - - - - ${file}")
    ) models
  );
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir}/models 0755 comfyui comfyui - -"
  ]
  ++ modelDirRules
  ++ modelLinkRules;
}
