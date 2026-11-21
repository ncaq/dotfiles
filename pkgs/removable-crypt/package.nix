# 暗号化されたリムーバブルデバイスをマウントしてアンマウントするコマンド。
#
# `mount`と`unmount`のサブコマンドを持つ。
# `lib/removable-crypt.nix`がデバイスごとに引数を付けて、`mnt-<名前>`と`umnt-<名前>`として包む。
# 手順は`src/RemovableCrypt/Mount.hs`と`src/RemovableCrypt/Unmount.hs`に書いてある。
{
  lib,
  haskell,
  localHaskellPackages,
  makeWrapper,
  btrfs-progs,
  snapper,
  systemd,
  util-linux,
}:
let
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
  package = localHaskellPackages.callCabal2nix "removable-crypt" source { };
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
  haskell.lib.compose.justStaticExecutables
]
