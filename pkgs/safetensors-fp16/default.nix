# safetensorsのF32テンソルだけをF16へ変換するコマンド。
#
# `lib/convert-safetensors-fp16.nix`がモデルの変換derivationから呼ぶ。
{
  lib,
  python3Packages,
}:
python3Packages.buildPythonApplication {
  pname = "safetensors-fp16";
  version = "0.1.0";
  pyproject = true;
  src = ./.;

  build-system = [ python3Packages.setuptools ];

  # safetensorsライブラリは使わない。
  # Python APIは全テンソルの辞書をメモリに要求する設計で、
  # 数十GBのファイルには使えない。
  dependencies = [
    python3Packages.numpy
    python3Packages.tqdm
  ];

  nativeCheckInputs = [
    python3Packages.pytestCheckHook
    # テストのリファレンス実装として本家のsafetensorsを使う。
    # 上の理由でこのパッケージ本体は使わないが、
    # テストが扱うのは数百バイトなのでメモリの制約は問題にならない。
    # 自前で書いたヘルパーで読み書きすると、
    # 実装と揃って同じ勘違いをしていても検出できない。
    python3Packages.safetensors
  ];

  pythonImportsCheck = [ "safetensors_fp16" ];

  meta = {
    description = "safetensorsのF32テンソルだけをF16へ変換するコマンド";
    mainProgram = "safetensors-fp16";
    license = lib.licenses.asl20;
  };
}
