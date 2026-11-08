# GGUFの`tokenizer.chat_template`を取り出して書き戻すコマンド。
#
# `lib/patch-gguf-chat-template.nix`がfixed-output derivationの中から呼ぶ。
# なぜテンプレートを差し替えるのかはそちらに、
# どうやって位置を求めるのかは`src/PatchGgufChatTemplate/Gguf/`の各モジュールの冒頭に、
# どうやって長さを保つのかは`src/PatchGgufChatTemplate/Pad.hs`の冒頭に書いてある。
#
# `callPackage`の結果に`haskell.lib`の関数を重ねると、
# `override`がこのファイルを`mkDerivation`付きで呼び直して壊れる。
# CIで警告をエラーにしたい時は`werror`で指定する。
{
  lib,
  haskell,
  haskellPackages,
  himari-src,
  werror ? false,
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
  (haskell.lib.compose.appendConfigureFlags (lib.optional werror "--ghc-options=-Werror"))
  # GGUFを組むderivationの閉包へGHCを持ち込まない。
  haskell.lib.compose.justStaticExecutables
]
