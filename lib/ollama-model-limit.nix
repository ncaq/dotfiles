/**
  OpenCodeのOllamaのproviderへ渡す、モデルごとのcontextの長さ。

  型: { lib } -> String -> AttrSet { limit = { context = Int; output = Int; }; }

  引数はアクセラレータ名(`cuda`か`cpu`)で、
  `lib/ollama-model-names.nix`のそのアクセラレータの全ての役割のモデルに`limit`を付ける。

  なぜ全ての役割に付けるか:
    OpenCodeは`ollama`というproviderのモデルを接続先の`/api/tags`から自動で発見するので、
    設定に書かなかったモデルも一覧に現れる。
    発見したモデルの`context`には`/api/show`の`*.context_length`を使うが、
    これはGGUFに書かれたモデルの最大長で、
    Ollamaが実際に確保する長さではない。
    Qwen3.8では262144と報告されるが、
    実際は`OLLAMA_CONTEXT_LENGTH`やモデルの`num_ctx`の長さで動いているため、
    `limit`を書かないとOpenCodeが使用率がまだ低いと見ている時点でcontextが溢れ、
    会話の圧縮も始まらない。
    役割を手で列挙すると、
    役割が増えたりモデルが別の役割へ移ったりした時に同じ不具合が黙って戻るので、
    表の全ての役割から組み立てる。
    埋め込みのモデルは`completion`の能力を持たず発見されないので、
    アクセラレータ別の表に無く対象にもならない。

  役割の間でモデル名が重なると、
  どちらの長さを使うべきか決まらないので評価を止める。

  `context`はモデルが一度に保持できるトークンの総数で、
  `output`は1回の応答の上限。
  配分の考え方は`lib/ollama-context.nix`にある。
*/
{ lib }:
let
  ollamaContext = import ./ollama-context.nix;
  modelNames = import ./ollama-model-names.nix;

  limitFor =
    accelerator:
    let
      roles = modelNames.${accelerator};
      # 翻訳のモデルだけはモデルの`num_ctx`で長さを固定している。
      lengthOf =
        role:
        if role == "translate" then ollamaContext.translateLength else ollamaContext.length.${accelerator};
      limitOf =
        contextLength:
        let
          budget = ollamaContext.budget contextLength;
        in
        {
          limit = {
            inherit (budget) context output;
          };
        };
    in
    lib.foldl' lib.attrsets.unionOfDisjoint { } (
      lib.mapAttrsToList (role: models: lib.genAttrs models (_: limitOf (lengthOf role))) roles
    );

  # 以下は末尾の`assert`のための表明。
  checkAccelerator =
    accelerator:
    let
      roles = modelNames.${accelerator};
      result = limitFor accelerator;
      allModels = lib.concatLists (lib.attrValues roles);
    in
    assert lib.assertMsg (
      lib.length allModels == lib.length (lib.unique allModels)
    ) "${accelerator}の役割の間でモデル名が重複しています";
    assert lib.assertMsg (
      lib.sort lib.lessThan (lib.attrNames result) == lib.sort lib.lessThan allModels
    ) "${accelerator}の全ての役割のモデルと`limit`を付けたモデルが一致しません";
    lib.all lib.id (
      lib.mapAttrsToList (
        role: models:
        lib.all (
          model:
          let
            # 期待値は上の`lengthOf`と`limitOf`を通さずに組み立てる。
            # 通すと、実装を取り違えても期待値も同じように取り違えて通ってしまう。
            budget = ollamaContext.budget (
              if role == "translate" then ollamaContext.translateLength else ollamaContext.length.${accelerator}
            );
          in
          lib.assertMsg (
            result.${model}.limit == {
              inherit (budget) context output;
            }
          ) "${accelerator}の${role}の${model}の`limit`が実際の長さと一致しません"
        ) models
      ) roles
    );
in
# 役割を手で列挙していた頃、
# 自由度優先と翻訳のモデルに`limit`が付かず、
# OpenCodeがGGUFの最大長を使ってcontextを溢れさせていた。
# 役割が増えたりモデルが別の役割へ移ったりしても同じ不具合が戻らないよう、
# 全ての役割の全てのモデルに、
# 実際に動かしている長さが付くことを表で確かめる。
#
# 呼び出し側が使うアクセラレータだけでなく、全てのアクセラレータで確かめる。
# 今呼んでいるのはCUDAのホストへ繋ぐ設定だけなので、
# 呼ばれた分だけを見るとCPUの側の表が壊れても気付けない。
# モデル名の表にはアクセラレータ別でない`embedding`もあるので、
# アクセラレータの一覧は長さの表から取る。
assert lib.all checkAccelerator (lib.attrNames ollamaContext.length);
limitFor
