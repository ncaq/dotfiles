# 暗号化されたリムーバブルデバイスをマウントしてアンマウントするコマンド。
#
# `mount`と`unmount`のサブコマンドを持つ。
# `lib/removable-crypt.nix`がデバイスごとに引数を付けて、`mnt-<名前>`と`umnt-<名前>`として包む。
# 手順は`src/RemovableCrypt/Mount.hs`と`src/RemovableCrypt/Unmount.hs`に書いてある。
#
# `callPackage`の結果に`haskell.lib`の関数を重ねると、
# `override`がこのファイルを`mkDerivation`付きで呼び直して壊れる。
# CIで警告をエラーにしたい時は`werror`で指定する。
{
  lib,
  haskell,
  haskellPackages,
  makeWrapper,
  btrfs-progs,
  snapper,
  systemd,
  util-linux,
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
      ./removable-crypt.cabal
      ./app
      ./src
      ./test
    ];
  };
  package = packages.callCabal2nix "removable-crypt" source { };
in
lib.pipe package [
  (haskell.lib.compose.overrideCabal (old: {
    buildTools = (old.buildTools or [ ]) ++ [ makeWrapper ];
    # 復号とマウントとスナップショットは外部コマンドに任せるので、PATHへ足して包む。
    postInstall = (old.postInstall or "") + ''
      wrapProgram "$out/bin/removable-crypt" \
        --prefix PATH : ${
          lib.makeBinPath [
            btrfs-progs
            snapper
            systemd
            util-linux
          ]
        }
    '';
  }))
  (haskell.lib.compose.appendConfigureFlags (lib.optional werror "--ghc-options=-Werror"))
  haskell.lib.compose.justStaticExecutables
]
