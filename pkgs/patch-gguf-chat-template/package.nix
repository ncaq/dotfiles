# GGUFの`tokenizer.chat_template`を取り出して書き戻すコマンド。
#
# `lib/patch-gguf-chat-template.nix`がfixed-output derivationの中から呼ぶ。
# なぜテンプレートを差し替えるのかはそちらに、
# どうやって位置を求めるのかは`src/PatchGgufChatTemplate/Gguf/`の各モジュールの冒頭に、
# どうやって長さを保つのかは`src/PatchGgufChatTemplate/Pad.hs`の冒頭に書いてある。
{
  lib,
  haskell,
  haskellPackages,
  himari-src,
}:
let
  packages = haskellPackages.extend (
    hself: _hsuper: {
      # himariはstableのnixpkgsではbrokenなので、上流のソースから組む。
      himari = hself.callCabal2nix "himari" himari-src { };
    }
  );
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
  package = packages.callCabal2nix "patch-gguf-chat-template" source { };
in
lib.pipe package [
  # GGUFを組むderivationのクロージャへGHCを持ち込まない。
  haskell.lib.compose.justStaticExecutables
]
