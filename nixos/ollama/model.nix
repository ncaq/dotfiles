# Ollamaに読み込ませるモデルの定義。
{
  lib,
  pkgs,
  hostName,
  ...
}:
let
  enableCuda = hostName == "bullet";
  fetchHuggingFace = import ../../lib/fetch-hugging-face.nix { inherit pkgs; };
  # ハードウェアの限界の範囲で汎用的に使えそうな知能のモデル。
  generalModels =
    if enableCuda then
      [
        # bulletは32GiBのVRAMに収まる範囲で汎用品質を優先して27Bモデルを使う。
        "qwen3.6:27b"
      ]
    else
      [
        # CPUで推論するホストは応答速度とMemoryMax内の余裕を両立する9Bモデルを使う。
        "qwen3.5:9b"
      ];
  # 表現の自由度を優先したモデル。
  freedomModels = {
    "mistralprism-24b:q4_k_m" = fetchHuggingFace {
      owner = "Aratako";
      repo = "MistralPrism-24B-GGUF";
      rev = "ef08191bef153caaa70e0720a8fcfa1cf11fb10b";
      file = "MistralPrism-24B-Q4_K_M.gguf";
      hash = "sha256-Tm9H9IXyhqSnPhzA0KZhwU8fNYWyK1XcdRKFGfB0Fdw=";
    };
    "qwen3-30b-a3b-erp-v0.1:q4_k_m" = fetchHuggingFace {
      owner = "Aratako";
      repo = "Qwen3-30B-A3B-ERP-v0.1-GGUF";
      rev = "78221ae35684a78dec965c1041c0bf10e0ff16d9";
      file = "Qwen3-30B-A3B-ERP-v0.1-Q4_K_M.gguf";
      hash = "sha256-Tzvnhjb74SOYzBIGvG4XqcYUelcaDLb5dTH0UrGpSAM=";
    };
    "ms3.2-24b-magnum-diamond:q4_k_m" = fetchHuggingFace {
      owner = "Doctor-Shotgun";
      repo = "MS3.2-24B-Magnum-Diamond-GGUF";
      rev = "7422a3599b749c9efa003c53f3165adc71e1f2aa";
      file = "MS3.2-24B-Magnum-Diamond-Q4_K_M.gguf";
      hash = "sha256-MLwAq6iPY52EsZwZ2bxVaHHQBGbDJuyc9U7F+Y6PVsQ=";
    };
  };
in
{
  options.local.ollama = {
    loadModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = "Ollama registryからpullするモデル。";
    };
    freedomModels = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      readOnly = true;
      description = "GGUFから`ollama create`で登録する表現自由度重視モデル。";
    };
  };

  config = {
    local.ollama = {
      loadModels = generalModels;
      inherit freedomModels;
    };
  };
}
