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
      model,
      rev,
      file,
      hash,
    }:
    pkgs.fetchurl {
      url = "https://huggingface.co/${owner}/${model}/resolve/${rev}/${file}";
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
        model = "waiIllustriousSDXL_v170";
        rev = "5ef4e2da7173a160ad04aebcaa2fdcd6d20ed792";
        file = "waiIllustriousSDXL_v170.safetensors";
        hash = "sha256-8Rawx4/0QUZ7DNyPGTbh7RjqMemZfHsTKxuNtTPwvQQ=";
      };
      # Illustrious-XLにdanbooru/e621約1300万枚を追加学習したモデル。
      # 画質とタグ網羅性に強い。非商用ライセンス。
      "NoobAI-XL-v1.1.safetensors" = fetchHuggingface {
        owner = "Laxhar";
        model = "noobai-XL-1.1";
        rev = "814a274af2b8097c0828819d561ec74c7d0c6cea";
        file = "NoobAI-XL-v1.1.safetensors";
        hash = "sha256-ZoHo5LE0yB8WUzrO2w1AbX5eNm4WJLQQUXjGTQCwXVE=";
      };
      # SDXLをアニメ画像で再学習したモデル。タグ設計が分かりやすい。
      "animagine-xl-4.0.safetensors" = fetchHuggingface {
        owner = "cagliostrolab";
        model = "animagine-xl-4.0";
        rev = "2b7c1b397761bf5bd3cc42e5b39ec99314a75a96";
        file = "animagine-xl-4.0.safetensors";
        hash = "sha256-HVtD/3W2q1mFAtTHedL7+j3OylHGDDtglkCmB3IzORY=";
      };
      # Illustrious系の公式ベースモデル。素の状態やマージ元として。
      "Illustrious-XL-v2.0.safetensors" = fetchHuggingface {
        owner = "OnomaAIResearch";
        model = "Illustrious-XL-v2.0";
        rev = "69459c1fe6f46db41ab31e6114f05acc0e06bcaa";
        file = "Illustrious-XL-v2.0.safetensors";
        hash = "sha256-wqGj6qE9TBB9x+AMP+gwyrQnqgJjYnQOoJR0WzQiozE=";
      };
    };
    controlnet = {
      # SDXL系全般で使えるControlNet統合モデル(ProMax版)。
      # openpose/lineart/tileなど複数のコントロールをこれ1つで扱える。
      "controlnet-union-sdxl-promax.safetensors" = fetchHuggingface {
        owner = "xinsir";
        model = "controlnet-union-sdxl-1.0";
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
        model = "adetailer";
        rev = "53cc19de382014514d9d4038601d261a7faa9b7b";
        file = "face_yolov8m.pt";
        hash = "sha256-cXkjwZs/S79SULco8fprLLcqM67R0jbqnK8OIa2UPl8=";
      };
    };
    upscale_models = {
      # アニメ絵向けの定番アップスケーラ。
      "4x-AnimeSharp.safetensors" = fetchHuggingface {
        owner = "Kim2091";
        model = "AnimeSharp";
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
