# ComfyUIの`models/`配下に宣言的に配置するモデルファイル群。
#
# モデルはNix storeへfetchurlで取得して、
# linkFarmでComfyUIのディレクトリ構造にまとめる。
# ComfyUIには追加モデル検索パスとして渡し、
# 書き込み可能なmodelsディレクトリはオンデマンド取得用に残す。
# storeのパスはホストのシステムクロージャから参照されるのでGCされない。
#
# CivitaiのダウンロードURLはAPIキーが必要なことがあり、
# fetchurlのビルド時にはsopsで管理するAPIキーを参照できないため、
# 認証なしで安定して取得できるHugging FaceのURLのみを使う。
# Civitaiからのオンデマンド取得はLoRA Manager(civitai.nix)が担う。
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
  fetchHuggingFace = import ../../../../lib/fetch-hugging-face.nix { inherit pkgs; };
  convertSafetensorsFp16 = import ../../../../lib/convert-safetensors-fp16.nix { inherit pkgs; };
  # 属性名は`models/`配下のディレクトリ名、
  # その中の属性名が配置するファイル名に対応する。
  models = {
    checkpoints = {
      # Illustrious-XLベースの人気マージモデル。日常使いの定番。
      # Civitaiオリジナルの非公式ミラーなので消失リスクがある。
      "waiIllustriousSDXL_v170.safetensors" = fetchHuggingFace {
        owner = "LyliaEngine";
        repo = "waiIllustriousSDXL_v170";
        rev = "5ef4e2da7173a160ad04aebcaa2fdcd6d20ed792";
        file = "waiIllustriousSDXL_v170.safetensors";
        hash = "sha256-8Rawx4/0QUZ7DNyPGTbh7RjqMemZfHsTKxuNtTPwvQQ=";
      };
      # SDXLをアニメ画像で再学習したモデル。
      # 通常版より人体、色、出力安定性を改善した公式Opt版を使う。
      "animagine-xl-4.0-opt.safetensors" = fetchHuggingFace {
        owner = "cagliostrolab";
        repo = "animagine-xl-4.0";
        rev = "2b7c1b397761bf5bd3cc42e5b39ec99314a75a96";
        file = "animagine-xl-4.0-opt.safetensors";
        hash = "sha256-YyfsqYv7ZTjdek7c4iSEobvFeoz/axHQddQNoa+4R6w=";
      };
    };
    # UNETLoaderが読むcheckpoint非統合の拡散モデル。
    diffusion_models = {
      # AnimaはCircleStone Labs Non-Commercial License v1.2。
      # モデル本体とfine-tune、merge、LoRAなどの派生モデルは、
      # 個人的な研究、実験、私的娯楽などの非商用かつ非production用途に限られる。
      # 企業内でも非production環境での評価と非商用R&Dまでで、
      # 有料API、公開生成サービス、収益化製品などの機能としての推論には別途商用ライセンスが必要。
      # 一方、生成画像は派生モデルに含まれず、販売、コミッション、広告、有料ゲーム、
      # などの素材を含む商用利用が明示的に許可されている。
      # https://huggingface.co/circlestone-labs/Anima/blob/f7382c4bf9d7ffe4ceea593a0adbb470c56dd79b/LICENSE.md
      # NVIDIA Cosmosの派生モデルでもあるため、NVIDIA Open Model Licenseも適用される。
      # https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/

      # 高品質と一貫性を優先した最新版。通常生成のデフォルトにする。
      "anima-aesthetic-v1.1.safetensors" = fetchHuggingFace {
        owner = "circlestone-labs";
        repo = "Anima";
        rev = "f7382c4bf9d7ffe4ceea593a0adbb470c56dd79b";
        file = "split_files/diffusion_models/anima-aesthetic-v1.1.safetensors";
        hash = "sha256-PBhoOHo6H/UEu7h8M2eDIZZerTgfz4evvQJk2qYAwII=";
      };
      # 既定画風の影響が弱く、作風の多様性とLoRA適性が最も高い基礎モデル。
      "anima-base-v1.0.safetensors" = fetchHuggingFace {
        owner = "circlestone-labs";
        repo = "Anima";
        rev = "f7382c4bf9d7ffe4ceea593a0adbb470c56dd79b";
        file = "split_files/diffusion_models/anima-base-v1.0.safetensors";
        hash = "sha256-vUO3z/4e0RU9nEHnvrLxjLEnPq+6o68+3WoXPckKAG4=";
      };
      # 指示文で画像を編集するQwen-Image-Editの2025年11月版。
      # Comfy-Org公式の再パッケージ版。Apache 2.0ライセンス。
      #
      # ConvRot INT8版を使う。
      # 量子化の前に重みへ256要素グループ単位のアダマール回転をかけて、
      # DiT特有の行方向の外れ値を分散させてからINT8にするQuaRot派生の方式で、
      # 回転なしのINT8より誤差が1桁近く小さくなる。
      # fp8mixed版は839層すべてのマーカーに`full_precision_matrix_mult`が立っていて、
      # ファイルサイズが半分になるだけで行列積は逆量子化したbf16で走る。
      # つまりこれはfp8からint8への乗り換えではなく、
      # bf16計算からint8計算への乗り換えになる。
      # RTX 5090の`4096x3072x3072`のlinearの実測では、
      # bf16の0.353msに対しConvRot INT8は0.169msだった。
      # 相対誤差はbf16の0.0017に対し0.0132で、
      # 回転なしINT8の0.0596より大幅に良い。
      # ファイルサイズはfp8mixedとほぼ同じなので保存側の増減はない。
      "qwen_image_edit_2511_int8_convrot.safetensors" = fetchHuggingFace {
        owner = "Comfy-Org";
        repo = "Qwen-Image-Edit_ComfyUI";
        rev = "e9e85de74a8f48c1e3e2656617626348675a2f21";
        file = "split_files/diffusion_models/qwen_image_edit_2511_int8_convrot.safetensors";
        hash = "sha256-EbWvWsYBgh1zkwyEhGyaFY5nF3NW2vknzhyNEPOWOCk=";
      };
      # Wan 2.2 I2V 14B MoEを高品質720pデータで4ステップ用に蒸留したfull expertモデル2つ。
      # LoRA近似ではなく蒸留済みの全重みを使い、
      # サンプリング前半をhigh noise、後半をlow noiseが担当する。
      # Apache 2.0ライセンス。
      #
      # この720p版は配布ファイルが全テンソルF32で1つ57GBあり、
      # high/lowの2つで114GBになる(非720p版はbf16で28GBだった)。
      # ComfyUIの計算dtypeはfp16で確定しているのに、
      # CPU側の重みはmmapしたファイル上のdtypeのまま保持されてキャストされないため、
      # 素のまま使うとシステムRAMを80GB以上消費してホストが応答しなくなる。
      # 事前にfp16へ落として半分にする。
      # fp16化した実測のピークは67.9GiBだった。
      # 丸めはround-to-nearest-evenでランタイムのキャストとビット一致するので、
      # 生成結果は変わらない。
      # 重みの最大絶対値は4.44で、fp16の上限65504に対して十分な余裕がある。
      "wan2.2_i2v_A14b_high_noise_lightx2v_4step_720p_260412.safetensors" =
        convertSafetensorsFp16
          (fetchHuggingFace {
            owner = "lightx2v";
            repo = "Wan2.2-Distill-Models";
            rev = "db93455b9e85c4d8a3ff9297fcfa189d213cfe29";
            file = "wan2.2_i2v_A14b_high_noise_lightx2v_4step_720p_260412.safetensors";
            hash = "sha256-NfRDFHG0ueWS6ZQcH18v0eG/JuFAHISt/gHdIrWyuGQ=";
          });
      "wan2.2_i2v_A14b_low_noise_lightx2v_4step_720p_260412.safetensors" =
        convertSafetensorsFp16
          (fetchHuggingFace {
            owner = "lightx2v";
            repo = "Wan2.2-Distill-Models";
            rev = "db93455b9e85c4d8a3ff9297fcfa189d213cfe29";
            file = "wan2.2_i2v_A14b_low_noise_lightx2v_4step_720p_260412.safetensors";
            hash = "sha256-kChH/FKj0w9naRXSrrhPwTxN+Sv2p5Q77uZprDTOPBU=";
          });
    };
    text_encoders = {
      # Animaが使うQwen3 0.6Bベースのテキストエンコーダ。
      "qwen_3_06b_base.safetensors" = fetchHuggingFace {
        owner = "circlestone-labs";
        repo = "Anima";
        rev = "f7382c4bf9d7ffe4ceea593a0adbb470c56dd79b";
        file = "split_files/text_encoders/qwen_3_06b_base.safetensors";
        hash = "sha256-zSpRIAPi+fPNPDKpw1c/gguyjJQPc8V7Hdqpg9kiPro=";
      };
      # Qwen-Image-Editで編集指示と入力画像を解析するVLM。
      # 画像理解と複雑な指示の精度を優先してBF16版を使う。
      "qwen_2.5_vl_7b.safetensors" = fetchHuggingFace {
        owner = "Comfy-Org";
        repo = "Qwen-Image_ComfyUI";
        rev = "46839d338df81ce625d5fae27d7e370314c0fbc9";
        file = "split_files/text_encoders/qwen_2.5_vl_7b.safetensors";
        hash = "sha256-z6/XOUWbyGJXOXJZ9hKpruiOW5joW1wNDRcX6JizRjo=";
      };
      # Wan系が使うテキストエンコーダ。
      # 複雑な動作やカメラ指示の追従精度を優先してFP16版を使う。
      "umt5_xxl_fp16.safetensors" = fetchHuggingFace {
        owner = "Comfy-Org";
        repo = "Wan_2.2_ComfyUI_Repackaged";
        rev = "fb1388adc906ab39ffc26ee40e96b22886b56bc4";
        file = "split_files/text_encoders/umt5_xxl_fp16.safetensors";
        hash = "sha256-e4hQ8ZYeHPinfMpMlko1jTA/SQgzxsCH0M/0svmdsq8=";
      };
    };
    vae = {
      # Qwen-Image系のVAE。
      "qwen_image_vae.safetensors" = fetchHuggingFace {
        owner = "Comfy-Org";
        repo = "Qwen-Image_ComfyUI";
        rev = "46839d338df81ce625d5fae27d7e370314c0fbc9";
        file = "split_files/vae/qwen_image_vae.safetensors";
        hash = "sha256-pwWA8CE+Z5Z+6clfBbtADo+wgwfgF6kkvzRBIj4CPR8=";
      };
      # Wan 2.2 14BはWan 2.1と共通のVAEを使う。
      "wan_2.1_vae.safetensors" = fetchHuggingFace {
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
      "controlnet-union-sdxl-promax.safetensors" = fetchHuggingFace {
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
      # 同じ学習データのYOLOv8mよりmAPが高いYOLOv9cを使う。
      "face_yolov9c.pt" = fetchHuggingFace {
        owner = "Bingsu";
        repo = "adetailer";
        rev = "53cc19de382014514d9d4038601d261a7faa9b7b";
        file = "face_yolov9c.pt";
        hash = "sha256-0C/kk8MeG7xkUPTcbx24agKlkyL/H20xjaBmHXLd0IQ=";
      };
    };
    upscale_models = {
      # hires fixは1.5倍しか要らないため、
      # 4倍モデルを通して0.375倍へ縮めるより2倍モデルを0.75倍へ縮める方が計算量が減る。
      # RCAN PixelUnshuffle版は作者いわく通常のRCAN版の約95%の品質で大幅に速い。
      # 実測では832x1216の入力に対して、
      # 4x-AnimeSharpの1.44秒や通常のRCAN版の0.88秒に対して0.36秒で済む。
      #
      # ライセンスはCC BY-NC-SA 4.0。
      # 表示と同一ライセンスでの継承を守れば非商用の範囲で再配布も改変もできて、
      # 商用利用だけが別途許諾を要する。
      # https://huggingface.co/Kim2091/2x-AnimeSharpV4
      #
      # RCAN PixelUnshuffleの読み込みにはspandrel 0.4.1以降が必要。
      # spandrelはutensils-comfyui-nix経由の推移的依存でこちらでは固定しておらず、
      # アーキテクチャの判定は評価時ではなくUpscaleModelLoaderの実行時に起きる。
      # 4x-AnimeSharpはESRGAN系で古いspandrelでも読めたため、これは新しく生じた制約になる。
      "2x-AnimeSharpV4_Fast_RCAN_PU.safetensors" = fetchHuggingFace {
        owner = "Kim2091";
        repo = "2x-AnimeSharpV4";
        rev = "1a9339b5c308ab3990f6233be2c1169a75772878";
        file = "2x-AnimeSharpV4_Fast_RCAN_PU.safetensors";
        hash = "sha256-tkHJ6xC0PyZTgXeqjw/vi5/CoVOv0UMdCgYqhMSc5tA=";
      };
    };
    # ComfyUI-SeedVR2_VideoUpscalerが登録する専用モデルディレクトリ。
    SEEDVR2 = {
      # 通常版はsharp版より線の過剰強調が少ないため、アニメ動画の標準にする。
      "seedvr2_ema_7b_fp16.safetensors" = fetchHuggingFace {
        owner = "numz";
        repo = "SeedVR2_comfyUI";
        rev = "09ced71023636e9bc8cdf9cdecfb2625d1e691e8";
        file = "seedvr2_ema_7b_fp16.safetensors";
        hash = "sha256-e4JBqpV2Bqts+2btq8ltQyNPmBnFOStE0kktnwsLvko=";
      };
      # 強い復元や輪郭の明瞭化が必要な素材向けの公式sharp版。
      # 過剰なディテールを生成する場合があるため通常版も残す。
      "seedvr2_ema_7b_sharp_fp16.safetensors" = fetchHuggingFace {
        owner = "numz";
        repo = "SeedVR2_comfyUI";
        rev = "09ced71023636e9bc8cdf9cdecfb2625d1e691e8";
        file = "seedvr2_ema_7b_sharp_fp16.safetensors";
        hash = "sha256-IKk+Af8kvq7rxd5OTlvpJDWWBsNWycUVCfuiRb0td90=";
      };
      "ema_vae_fp16.safetensors" = fetchHuggingFace {
        owner = "numz";
        repo = "SeedVR2_comfyUI";
        rev = "09ced71023636e9bc8cdf9cdecfb2625d1e691e8";
        file = "ema_vae_fp16.safetensors";
        hash = "sha256-IGeFSPQg2Y0m8RRC01KPi4yU5X7gRu+T27djPahhLKE=";
      };
    };
  };
  modelDir = pkgs.linkFarm "comfyui-models" (
    lib.flatten (
      lib.mapAttrsToList (
        category:
        lib.mapAttrsToList (
          name: path: {
            name = "${category}/${name}";
            inherit path;
          }
        )
      ) models
    )
  );
  extraModelPaths = (pkgs.formats.yaml { }).generate "comfyui-extra-model-paths.yaml" {
    nix = {
      base_path = modelDir;
      checkpoints = "checkpoints";
      controlnet = "controlnet";
      diffusion_models = "diffusion_models";
      loras = "loras";
      seedvr2 = "SEEDVR2";
      text_encoders = "text_encoders";
      ultralytics = "ultralytics";
      ultralytics_bbox = "ultralytics/bbox";
      upscale_models = "upscale_models";
      vae = "vae";
    };
  };
in
{
  options.local.comfyui.models = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf lib.types.package);
    readOnly = true;
    description = "ComfyUIのmodelsディレクトリへ配置するモデル。";
  };

  config = {
    local.comfyui.models = models;
    containers.comfyui.config.services.comfyui.extraArgs = [
      "--extra-model-paths-config"
      "${extraModelPaths}"
    ];
    systemd.tmpfiles.rules = [ "d ${dataDir}/models 0755 comfyui comfyui - -" ];
  };
}
