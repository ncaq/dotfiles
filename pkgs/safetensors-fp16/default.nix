# safetensorsのF32テンソルだけをF16へ変換するコマンド。
#
# `lib/convert-safetensors-fp16.nix`がモデルの変換derivationから呼ぶ。
#
# Rustで書いているのは、safetensorsの上流の実装が`safetensors`クレートだからである。
# ComfyUIが読み込みに使うPythonのsafetensorsも同じ上流の実装で、
# 同じクレートで読み書きすれば形式の互換性で面倒が起きにくい。
# 補助プログラムの言語の基準では、問題を手っ取り早く解決できるライブラリがある場合に当たる。
{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "safetensors-fp16";
  version = "0.2.0";
  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "safetensorsのF32テンソルだけをF16へ変換するコマンド";
    mainProgram = "safetensors-fp16";
    license = lib.licenses.asl20;
  };
}
