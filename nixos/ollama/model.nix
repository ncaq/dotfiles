# Ollamaに読み込ませるモデルの定義。
{
  lib,
  pkgs,
  config,
  ...
}:
let
  enableCuda = config.local.ollama.enableCuda;
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
        # CPUの推論はメモリ帯域で頭打ちになり、
        # 1トークンごとに読み出す重みの量がそのまま速度を決める。
        # 総パラメータではなくactive parameterが効くため、
        # 同じ品質帯ならdenseよりMoEの方が圧倒的に速い。
        # seminarでの実測では9Bのdenseが約10トークン/秒に対し、
        # このactive 3BのMoEは約19トークン/秒だった。
        "qwen3.6:35b-a3b"
      ];
  # 表現の自由度を優先したモデル。
  # CPUで推論するホストには置かない。
  # seminarでの実測では24Bのdenseは約4トークン/秒しか出ず、
  # 対話を待っていられる速度ではないため、
  # ディスクとロード時間を消費するだけになる。
  freedomModels = lib.optionalAttrs enableCuda {
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
  local.ollama = {
    loadModels = generalModels;
    inherit freedomModels;
  };
}
