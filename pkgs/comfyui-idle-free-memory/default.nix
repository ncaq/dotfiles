# アイドル中のComfyUIにメモリを解放させる常駐プロセス。
#
# `nixos/host/bullet/comfyui/idle-free-memory.nix`がコンテナの中のサービスとして動かす。
# 何をどう判断して解放するかは`src/IdleFreeMemory/Run.hs`の冒頭に書いてある。
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
      ./comfyui-idle-free-memory.cabal
      ./app
      ./src
      ./test
    ];
  };
  package = packages.callCabal2nix "comfyui-idle-free-memory" source { };
in
lib.pipe package [
  (haskell.lib.compose.appendConfigureFlags (lib.optional werror "--ghc-options=-Werror"))
  # コンテナの閉包へGHCを持ち込まない。
  haskell.lib.compose.justStaticExecutables
]
