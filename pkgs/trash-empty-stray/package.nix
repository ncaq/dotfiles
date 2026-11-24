# `trash-empty --all-users`が見つけられないゴミ箱を探して掃除するコマンド。
#
# 同じディレクトリの`module.nix`が定義する`trash-empty-stray.service`から呼ばれる。
# 何を探してどう掃除するかは`src/TrashEmptyStray/Cli.hs`に書いてある。
{
  lib,
  haskell,
  localHaskellPackages,
  makeWrapper,
  testers,
  trash-cli,
  util-linux,
}:
let
  # 動かすものだけをstoreへ入れる。
  # ディレクトリをそのまま渡すと`dist-newstyle`のような作業中のファイルまで付いてくる。
  source = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./trash-empty-stray.cabal
      ./app
      ./src
      ./test
    ];
  };
  package = localHaskellPackages.callCabal2nix "trash-empty-stray" source { };
in
lib.pipe package [
  (haskell.lib.compose.overrideCabal (old: {
    buildTools = (old.buildTools or [ ]) ++ [ makeWrapper ];
    # 期限の判定は`trash-empty`に任せるので、テストでも実物を呼ぶ。
    testToolDepends = (old.testToolDepends or [ ]) ++ [ trash-cli ];
    # `sweep`は実行ファイル自身を`clean-here`として起動するので、テストでもビルドした実物を呼ぶ。
    # cabalは`build-tool-depends`に書いた自分の実行ファイルをPATHへ入れるが、
    # nixpkgsの`Setup`でのビルドでは入らないので、ここで足す。
    preCheck = (old.preCheck or "") + ''
      export PATH="$PWD/dist/build/trash-empty-stray:$PATH"
    '';
    # 期限切れのエントリを消すのは`trash-empty`に、
    # ゴミ箱の所有者の権限へ落とすのは`setpriv`に任せるので、PATHへ足して包む。
    postInstall = (old.postInstall or "") + ''
      wrapProgram "$out/bin/trash-empty-stray" \
        --prefix PATH : ${
          lib.makeBinPath [
            trash-cli
            util-linux
          ]
        }
    '';
  }))
  haskell.lib.compose.justStaticExecutables
  # 権限を落とす場面はsandwichのテストでは確かめられないので、コンテナの中で実際のユニットを動かす。
  # 配るもののstoreパスに関わらないように、`checkPhase`ではなく`passthru.tests`に置く。
  (
    package:
    package.overrideAttrs (old: {
      passthru = (old.passthru or { }) // {
        tests = (old.passthru.tests or { }) // {
          nixos = import ./nixos-test.nix { inherit testers; };
        };
      };
    })
  )
]
