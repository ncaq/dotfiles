# `secrets/cachix.yaml`から認証トークンを復号して、
# `cachix push ncaq`を実行するラッパ。
{
  lib,
  haskell,
  haskellPackages,
  makeWrapper,
  cachix,
  sops,
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
      ./cachix-push-ncaq.cabal
      ./app
      ./src
      ./test
    ];
  };
  package = packages.callCabal2nix "cachix-push-ncaq" source { };
in
lib.pipe package [
  (haskell.lib.compose.overrideCabal (old: {
    buildTools = (old.buildTools or [ ]) ++ [ makeWrapper ];
    # 復号は`sops`に、転送は`cachix`に任せるので、PATHへ足して包む。
    postInstall = (old.postInstall or "") + ''
      wrapProgram "$out/bin/cachix-push-ncaq" \
        --prefix PATH : ${
          lib.makeBinPath [
            cachix
            sops
          ]
        }
    '';
  }))
  haskell.lib.compose.justStaticExecutables
]
