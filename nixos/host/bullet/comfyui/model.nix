# ComfyUIの`models/`配下に宣言的に配置するモデルファイル群。
#
# モデルはNix storeへ`lib/fetch-hugging-face.nix`で取得して、
# linkFarmでComfyUIのディレクトリ構造にまとめる。
# ComfyUIには追加モデル検索パスとして渡し、
# 書き込み可能なmodelsディレクトリはオンデマンド取得用に残す。
# storeのパスはホストのシステムクロージャから参照されるのでGCされない。
#
# CivitaiのダウンロードURLはAPIキーが必要なことがあり、
# ビルド環境へAPIキーを持ち込む仕組みをCivitai向けには用意していないため、
# 認証なしでも安定して取得できるHugging Faceのリポジトリのみを使う。
# Civitaiからのオンデマンド取得はLoRA Manager(civitai.nix)が担う。
# リポジトリの更新でハッシュがずれないように、
# リビジョンは`main`ではなくcommit hashで固定する。
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
      # https://huggingface.co/circlestone-labs/Anima/blob/f973fc41ec7545364ac9776c2440285f43ff2a30/LICENSE.md
      # NVIDIA Cosmosの派生モデルでもあるため、NVIDIA Open Model Licenseも適用される。
      # https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/

      # 高品質と一貫性を優先した最新版。通常生成のデフォルトにする。
      "anima-aesthetic-v1.1.safetensors" = fetchHuggingFace {
        owner = "circlestone-labs";
        repo = "Anima";
        rev = "f973fc41ec7545364ac9776c2440285f43ff2a30";
        file = "split_files/diffusion_models/anima-aesthetic-v1.1.safetensors";
        hash = "sha256-PBhoOHo6H/UEu7h8M2eDIZZerTgfz4evvQJk2qYAwII=";
      };
      # 既定画風の影響が弱く、作風の多様性とLoRA適性が最も高い基礎モデル。
      "anima-base-v1.0.safetensors" = fetchHuggingFace {
        owner = "circlestone-labs";
        repo = "Anima";
        rev = "f973fc41ec7545364ac9776c2440285f43ff2a30";
        file = "split_files/diffusion_models/anima-base-v1.0.safetensors";
        hash = "sha256-vUO3z/4e0RU9nEHnvrLxjLEnPq+6o68+3WoXPckKAG4=";
      };
      # Qwen-Image-2.1はQwen Research License Agreement。
      # 本体、テキストエンコーダ、VAE、プロンプトリライト用のPEモデルのすべてが対象で、
      # 利用、複製、改変、派生物の作成は研究または評価目的の非商用に限られる。
      # 商用利用には別途Alibabaからの商用ライセンスが必要。
      # Animaと違い生成画像を商用利用してよいという明示的な許可は無く、
      # 商用目的で生成すること自体がMaterialsの商用利用に当たると読める。
      # 生成物を使ってAIモデルを学習し配布する場合は「Built with Qwen」の表示も要る。
      # https://huggingface.co/Qwen/Qwen-Image-2.1/blob/790c92633540aa0cb11d9abf19eb46d861714758/LICENSE
      # 以前のQwen-Image-Edit 2511はApache 2.0だったので、
      # 2.1への乗り換えで制約が強まっている。
      #
      # 生成と指示ベースの編集を1つの7Bモデルで行う。
      # Comfy-Org公式の再パッケージ版。
      #
      # ConvRot INT8版を使う。
      # 量子化の前に重みへ256要素グループ単位のアダマール回転をかけて、
      # DiT特有の行方向の外れ値を分散させてからINT8にするQuaRot派生の方式で、
      # 回転なしのINT8より誤差が1桁近く小さくなる。
      # 行列積もINT8のまま走るので、bf16版より計算そのものが速い。
      # RTX 5090の`4096x3072x3072`のlinearの実測では、
      # bf16の0.353msに対しConvRot INT8は0.169msだった。
      # 相対誤差はbf16の0.0017に対し0.0132で、
      # 回転なしINT8の0.0596より大幅に良い。
      # サンプリングで毎ステップ回るのがこのモデルなので、ここは速度を取る。
      "qwen_image_2.1_int8_convrot.safetensors" = fetchHuggingFace {
        owner = "Comfy-Org";
        repo = "Qwen-Image-2.1";
        rev = "9a44dbdb47cefd046be9c0a13476192f34c8db8e";
        file = "diffusion_models/qwen_image_2.1_int8_convrot.safetensors";
        hash = "sha256-y3QRPLA/rs15YRsB/X/WQvCqYNbwuVCGq+4hTXXqpX0=";
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
      #
      # 変換後のhashで出力パスを固定するfixed-output derivationなので、
      # 変換ツールやPythonが更新されても再変換と原本の再取得は走らない。
      "wan2.2_i2v_A14b_high_noise_lightx2v_4step_720p_260412.safetensors" = convertSafetensorsFp16 {
        src = fetchHuggingFace {
          owner = "lightx2v";
          repo = "Wan2.2-Distill-Models";
          rev = "db93455b9e85c4d8a3ff9297fcfa189d213cfe29";
          file = "wan2.2_i2v_A14b_high_noise_lightx2v_4step_720p_260412.safetensors";
          hash = "sha256-NfRDFHG0ueWS6ZQcH18v0eG/JuFAHISt/gHdIrWyuGQ=";
        };
        hash = "sha256-nXzTJqI2bQI91BEfAqvlgPwJ31UBqnbNgmSv3OEUnvQ=";
      };
      "wan2.2_i2v_A14b_low_noise_lightx2v_4step_720p_260412.safetensors" = convertSafetensorsFp16 {
        src = fetchHuggingFace {
          owner = "lightx2v";
          repo = "Wan2.2-Distill-Models";
          rev = "db93455b9e85c4d8a3ff9297fcfa189d213cfe29";
          file = "wan2.2_i2v_A14b_low_noise_lightx2v_4step_720p_260412.safetensors";
          hash = "sha256-kChH/FKj0w9naRXSrrhPwTxN+Sv2p5Q77uZprDTOPBU=";
        };
        hash = "sha256-rRVdtZzj/Eays5/iG+8vDG+hwYkysw4Cn327hS8veKU=";
      };
    };
    text_encoders = {
      # Animaが使うQwen3 0.6Bベースのテキストエンコーダ。
      "qwen_3_06b_base.safetensors" = fetchHuggingFace {
        owner = "circlestone-labs";
        repo = "Anima";
        rev = "f973fc41ec7545364ac9776c2440285f43ff2a30";
        file = "split_files/text_encoders/qwen_3_06b_base.safetensors";
        hash = "sha256-zSpRIAPi+fPNPDKpw1c/gguyjJQPc8V7Hdqpg9kiPro=";
      };
      # Qwen-Image-2.1で指示文と参照画像を解析するQwen3-VL 8B。
      # ライセンスは拡散モデル本体の所に書いたQwen Research License。
      # 1回の実行で1度しか回らず速度の寄与が小さいので、
      # 画像理解と複雑な指示の精度を優先してBF16版を使う。
      "qwen3vl_8b_bf16.safetensors" = fetchHuggingFace {
        owner = "Comfy-Org";
        repo = "Qwen-Image-2.1";
        rev = "9a44dbdb47cefd046be9c0a13476192f34c8db8e";
        file = "text_encoders/qwen3vl_8b_bf16.safetensors";
        hash = "sha256-aL3IK8G2aFEWKuZWIl5+IGgWa2A9sZvV1aO5DrEmaak=";
      };
      # Qwen-Image-2.1公式の編集指示リライト用モデルPE-I2Iから、
      # hereticで拒否の方向を取り除いた版。
      # PE-I2IはQwen3.5 9Bを2.1の指示文の書式へ合わせてfine-tuneしたもので、
      # 日本語の指示と参照画像から英文の編集命令を書き下す。
      # テキストエンコーダとしてではなく`RewriteEditPrompt`が文章生成に使う。
      #
      # 公式のPE-I2Iは指示によっては拒否して、
      # 編集せず元画像をそのまま出す指示へ書き換えてしまう。
      # 公式のシステムプロンプトには安全に関する記述が無く、
      # 規制は重みに学習されているので、プロンプトの側では外せない。
      # 自分のGPUで動かすローカルモデルなので、
      # 指示どおりに書き換えさせるためにheretic版を使う。
      #
      # hereticは拒否率と元のモデルからの出力分布のずれを同時に最小化するので、
      # 書式や回答形式への追従は保たれやすい。
      # 拒否の方向を取り除いたのは`darrellbest/Qwen-Image-2.1-PE-I2I-Heretic`で、
      # このリポジトリはそれをComfy-Orgの`comfy-model-tools`でConvRot INT8へ変換したもの。
      # テンソルの構成と量子化のメタデータはComfy-Org公式のPE-I2Iと一致する。
      # 同梱のシステムプロンプトも公式と同一なので、
      # `custom-node.nix`が公式リポジトリから配置するものをそのまま使える。
      # ライセンスは元と同じく拡散モデル本体の所に書いたQwen Research License。
      "qwen3.5_9b_qwen_image_2.1_pe_i2i_heretic.int8_convrot.safetensors" = fetchHuggingFace {
        owner = "Adahm";
        repo = "PE-Heretic-INT8-ConvRot-for-Qwen-Image-2.1";
        rev = "afc1c843a7e549574e8e8186bb383b17d8072e12";
        file = "qwen3.5_9b_qwen_image_2.1_pe_i2i_heretic.int8_convrot.safetensors";
        hash = "sha256-l5uQY90WZF8Bkcn/VapQWRBb/oQJbZaoF6hd7tIiMfA=";
      };
      # Wan系が使うテキストエンコーダ。
      # 複雑な動作やカメラ指示の追従精度を優先してFP16版を使う。
      "umt5_xxl_fp16.safetensors" = fetchHuggingFace {
        owner = "Comfy-Org";
        repo = "Wan_2.2_ComfyUI_Repackaged";
        rev = "ee6f4a40737a995bf5818954cfce6d59443b0f04";
        file = "split_files/text_encoders/umt5_xxl_fp16.safetensors";
        hash = "sha256-e4hQ8ZYeHPinfMpMlko1jTA/SQgzxsCH0M/0svmdsq8=";
      };
    };
    vae = {
      # Qwen-Image系のVAE。
      # Qwen-Image-2.1とは互換性が無く、Animaが使う。
      "qwen_image_vae.safetensors" = fetchHuggingFace {
        owner = "Comfy-Org";
        repo = "Qwen-Image_ComfyUI";
        rev = "6469d02bfbf02a049223ba3ae3497ef9ae8220b9";
        file = "split_files/vae/qwen_image_vae.safetensors";
        hash = "sha256-pwWA8CE+Z5Z+6clfBbtADo+wgwfgF6kkvzRBIj4CPR8=";
      };
      # Qwen-Image-2.1専用のVAE。
      # 64チャンネルで空間16倍縮小の新しい構造で、RGBAも扱える。
      # ライセンスは拡散モデル本体の所に書いたQwen Research License。
      "qwen_image_2.1_vae_bf16.safetensors" = fetchHuggingFace {
        owner = "Comfy-Org";
        repo = "Qwen-Image-2.1";
        rev = "9a44dbdb47cefd046be9c0a13476192f34c8db8e";
        file = "vae/qwen_image_2.1_vae_bf16.safetensors";
        hash = "sha256-uyH3RzBR4aw2hRXdPy4VzUTXoRdI7ogj4d3KPkh2t8k=";
      };
      # Wan 2.2 14BはWan 2.1と共通のVAEを使う。
      "wan_2.1_vae.safetensors" = fetchHuggingFace {
        owner = "Comfy-Org";
        repo = "Wan_2.2_ComfyUI_Repackaged";
        rev = "ee6f4a40737a995bf5818954cfce6d59443b0f04";
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
