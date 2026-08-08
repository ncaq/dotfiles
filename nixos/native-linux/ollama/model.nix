# Ollamaに読み込ませるモデルの定義。
{
  lib,
  hostName,
  ...
}:
let
  enableCuda = hostName == "bullet";
  # ハードウェアの限界の範囲で汎用的に使えそうな知能のモデル。
  generalModels =
    if enableCuda then
      [
        # bulletは32GiBのVRAMに収まる範囲で汎用品質を優先して27Bモデルを使う。
        "qwen3.6:27b"
      ]
    else
      [
        # CPUで推論するcreepとseminarは応答速度とMemoryMax内の余裕を両立する9Bモデルを使う。
        "qwen3.5:9b"
      ];
  loadModels = generalModels;
in
{
  options.local.ollama.loadModels = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    readOnly = true;
    description = "`services.ollama.loadModels`に読み込ませるモデル。";
  };

  config = {
    local.ollama.loadModels = loadModels;
  };
}
