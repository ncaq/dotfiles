# `lib/ollama-model-limit.nix`がOpenCodeへ渡す長さを確かめる。
#
# 役割を手で列挙していた頃、
# 自由度優先と翻訳のモデルに`limit`が付かず、
# OpenCodeがGGUFの最大長を使ってcontextを溢れさせていた。
# 役割が増えたりモデルが別の役割へ移ったりしても同じ不具合が戻らないよう、
# 全ての役割の全てのモデルに、
# 実際に動かしている長さが付くことを表で確かめる。
{ lib }:
let
  modelLimit = import ../../lib/ollama-model-limit.nix { inherit lib; };
  ollamaContext = import ../../lib/ollama-context.nix;
  modelNames = import ../../lib/ollama-model-names.nix;

  checkAccelerator =
    accelerator:
    let
      roles = modelNames.${accelerator};
      result = modelLimit accelerator;
      expectedLength =
        role:
        if role == "translate" then ollamaContext.translateLength else ollamaContext.length.${accelerator};
      allModels = lib.concatLists (lib.attrValues roles);
      checkRole =
        role: models:
        lib.all (
          model:
          let
            budget = ollamaContext.budget (expectedLength role);
          in
          lib.assertMsg (
            result.${model}.limit == {
              inherit (budget) context output;
            }
          ) "${accelerator}の${role}の${model}の`limit`が実際の長さと一致しません"
        ) models;
    in
    assert lib.assertMsg (
      lib.length allModels == lib.length (lib.unique allModels)
    ) "${accelerator}の役割の間でモデル名が重複しています";
    assert lib.assertMsg (
      lib.sort lib.lessThan (lib.attrNames result) == lib.sort lib.lessThan allModels
    ) "${accelerator}の全ての役割のモデルと`limit`を付けたモデルが一致しません";
    lib.all lib.id (lib.mapAttrsToList checkRole roles);
in
assert checkAccelerator "cuda";
assert checkAccelerator "cpu";
true
