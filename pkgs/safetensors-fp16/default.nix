# safetensorsのF32テンソルだけをF16へ変換するコマンド。
#
# `lib/convert-safetensors-fp16.nix`がモデルの変換derivationから呼ぶ。
{
  lib,
  runCommand,
  makeWrapper,
  python3,
  ruff,
}:
let
  # 依存はnumpyと進捗表示のtqdmだけに抑える。
  # safetensorsライブラリのPython APIは全テンソルの辞書をメモリに要求する設計で、
  # 数十GBのファイルには使えない。
  pythonEnv = python3.withPackages (ps: [
    ps.numpy
    ps.tqdm
  ]);
  source = ./safetensors_fp16;
in
runCommand "safetensors-fp16"
  {
    nativeBuildInputs = [ makeWrapper ];
    meta.mainProgram = "safetensors-fp16";
  }
  ''
    # treefmtと同じlintをビルド時にも通して、
    # 構文エラーを抱えたまま数十GBの変換ビルドに入らないようにする。
    # `pkgs.writers.writePython3`は使わない。
    # 内部のチェッカがflake8で、
    # このリポジトリの標準であるruff-formatの88桁とE501の79桁が衝突するため。
    # `--isolated`はサンドボックス内でリポジトリの設定を探しに行かせないため、
    # `--no-cache`は書き込み可能なキャッシュディレクトリが無いため。
    ${lib.getExe ruff} check --no-cache --isolated ${source}

    mkdir -p $out/libexec/safetensors-fp16
    cp -r ${source} $out/libexec/safetensors-fp16/safetensors_fp16
    makeWrapper ${lib.getExe pythonEnv} $out/bin/safetensors-fp16 \
      --add-flags "-m safetensors_fp16" \
      --prefix PYTHONPATH : $out/libexec/safetensors-fp16
  ''
