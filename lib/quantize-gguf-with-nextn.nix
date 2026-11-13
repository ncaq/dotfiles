/**
  quantizeGgufWithNextn: 本体のGGUFへ別ファイルのMTPのNextN層を足して量子化したGGUFを作る関数。

  型: { pkgs } -> { name, model, draft, type, hash } -> derivation

  引数:
    pkgs  - `merge-gguf-nextn`とllama.cppを取るnixpkgs。
            NextN層を持つアーキテクチャを量子化できる程度に新しいllama.cppが要るので、
            呼び出し側はunstableを渡す。
    name  - 出力のファイル名
    model - NextN層を持たない本体のGGUF。量子化前のBF16などを渡す。
    draft - 本体と同じ変換で切り出されたNextN層を持つGGUF
    type  - `llama-quantize`へ渡す量子化の種類(`Q6_K`など)
    hash  - 量子化した後のファイルのSRI形式sha256ハッシュ

  なぜ必要か:
    OllamaでMTPの投機的デコーディングを使うには、
    NextN層が本体と同じGGUFに入っている必要がある。
    今のOllamaにはドラフトを指定する`DRAFT`があるが、
    NextN層だけのGGUFを渡せるかは確かめていない。
    別ファイルのドラフトヘッドを`FROM`へ並べると壊れる理由は`nixos/ollama/model.nix`にある。
    ggml-orgのように本体とドラフトヘッドを分けて配る配布元からは、
    まとめたGGUFを自分で作るしかない。

  なぜ量子化の前にまとめるか:
    `llama-quantize`は層ごとに量子化の種類を選ぶ時に、
    メタデータの層数と実際の注意機構のテンソルの数が合うことを前提にしている。
    ドラフトヘッドだけのGGUFは層数が本体の分まで数えているのにテンソルはNextN層の分しか無く、
    単独では量子化できない。
    まとめてから1回量子化すれば、
    変換時にNextN層を捨てずに書き出したものを量子化した場合と同じ結果になる。

  なぜfixed-output derivationにするか:
    `lib/patch-gguf-chat-template.nix`と同じ理由で、
    flake.lockの更新のたびに同じ中身が別のパスになり、
    数十GBの再ビルドと再取得が走るのを避けるためである。
    imatrixを使わない量子化は決定的なので、
    量子化した後のhashで出力パスを固定できる。

    入力のBF16は量子化した後の数倍の大きさがある。
    出力がstoreかバイナリキャッシュにある限り入力は取得されないので、
    GCで消えても困らない。

  hashの更新を忘れると古い出力が使われ続ける:
    出力パスは名前とhashだけで決まるので、
    入力や量子化の種類を変えてもhashがそのままなら既にある出力がそのまま使われる。
    入力を変えた時は必ずhashも更新する。
    `hash = ""`で一度ビルドして、
    hash mismatchのエラーに出る実際の値を書き写す。
*/
{ pkgs }:
let
  mergeGgufNextn = pkgs.callPackage ../pkgs/merge-gguf-nextn { };
in
{
  name,
  model,
  draft,
  type,
  hash,
}:
pkgs.runCommand name
  {
    nativeBuildInputs = [
      mergeGgufNextn
      pkgs.llama-cpp
    ];

    outputHashMode = "flat";
    outputHashAlgo = "sha256";
    outputHash = hash;

    # 入力は数十GBあり手元で取得済みのことが多いので、リモートビルダーへ送らない。
    preferLocalBuild = true;
  }
  ''
    # まとめた量子化前のファイルは出力の数倍の大きさがあるが、
    # 量子化の入力にしか使わないのでビルド用の一時領域へ置く。
    merge-gguf-nextn ${model} ${draft} merged.gguf
    llama-quantize merged.gguf "$out" ${pkgs.lib.escapeShellArg type} "$NIX_BUILD_CORES"
  ''
