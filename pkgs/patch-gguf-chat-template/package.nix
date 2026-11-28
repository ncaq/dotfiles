# GGUFの`tokenizer.chat_template`を取り出して書き戻すコマンド。
#
# 隣の`builder.nix`がfixed-output derivationの中から呼ぶ。
# なぜテンプレートを差し替えるのかはそちらに、
# どうやって位置を求めるのかは`src/PatchGgufChatTemplate/Gguf/`の各モジュールの冒頭に、
# どうやって長さを保つのかは`src/PatchGgufChatTemplate/Pad.hs`の冒頭に書いてある。
{
  lib,
  haskell,
  localHaskellPackages,
}:
let
  # 動かすものだけをstoreへ入れる。
  # ディレクトリをそのまま渡すと`dist-newstyle`のような作業中のファイルまで付いてくる。
  source = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./patch-gguf-chat-template.cabal
      ./app
      ./src
      ./test
    ];
  };
  package = localHaskellPackages.callCabal2nix "patch-gguf-chat-template" source { };
in
lib.pipe package [
  # GGUFを組むderivationのクロージャへGHCを持ち込まない。
  haskell.lib.compose.justStaticExecutables
]
