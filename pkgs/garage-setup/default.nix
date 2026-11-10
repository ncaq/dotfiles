# GarageのS3バケットとキーを用意するコマンド。
#
# `lib/garage-setup.nix`が作るサービスから呼ばれる。
# 何をするかは`src/GarageSetup/Setup.hs`に、
# 入力の環境変数は`src/GarageSetup/Config.hs`に書いてある。
#
# Admin APIは自前でHTTPを叩くので、外部コマンドへの依存は無い。
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
      ./garage-setup.cabal
      ./app
      ./src
      ./test
    ];
  };
  package = packages.callCabal2nix "garage-setup" source { };
in
lib.pipe package [
  (haskell.lib.compose.appendConfigureFlags (lib.optional werror "--ghc-options=-Werror"))
  # seminarの閉包へGHCを持ち込まない。
  haskell.lib.compose.justStaticExecutables
]
