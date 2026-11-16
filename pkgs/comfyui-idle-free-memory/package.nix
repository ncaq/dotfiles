# アイドル中のComfyUIにメモリを解放させる常駐プロセス。
#
# `nixos/host/bullet/comfyui/idle-free-memory.nix`がコンテナの中のサービスとして動かす。
# 何をどう判断して解放するかは`src/IdleFreeMemory/Run.hs`の冒頭に書いてある。
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
      ./comfyui-idle-free-memory.cabal
      ./app
      ./src
      ./test
    ];
  };
  package = packages.callCabal2nix "comfyui-idle-free-memory" source { };
in
lib.pipe package [
  # コンテナの閉包へGHCを持ち込まない。
  haskell.lib.compose.justStaticExecutables
]
