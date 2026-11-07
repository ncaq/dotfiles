# safetensorsのF32テンソルだけをF16へ変換するコマンド。
#
# `lib/convert-safetensors-fp16.nix`がモデルの変換derivationから呼ぶ。
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
