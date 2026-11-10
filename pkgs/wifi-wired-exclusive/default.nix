# 有線接続中はWiFiの接続を切り、有線が無くなったら繋ぎ直すNetworkManagerのdispatcherスクリプト。
#
# `nixos/native-linux/wifi-wired-exclusive.nix`から呼ばれる。
# 何をどう決めるかは`src/WifiWiredExclusive/Plan.hs`に書いてある。
#
# `callPackage`の結果に`haskell.lib`の関数を重ねると、
# `override`がこのファイルを`mkDerivation`付きで呼び直して壊れる。
# CIで警告をエラーにしたい時は`werror`で指定する。
{
  lib,
  haskell,
  haskellPackages,
  makeWrapper,
  networkmanager,
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
      ./wifi-wired-exclusive.cabal
      ./app
      ./src
      ./test
    ];
  };
  package = packages.callCabal2nix "wifi-wired-exclusive" source { };
in
lib.pipe package [
  (haskell.lib.compose.overrideCabal (old: {
    buildTools = (old.buildTools or [ ]) ++ [ makeWrapper ];
    # デバイスの状態の取得と操作は`nmcli`に任せるので、PATHへ足して包む。
    postInstall = (old.postInstall or "") + ''
      wrapProgram "$out/bin/wifi-wired-exclusive" \
        --prefix PATH : ${lib.makeBinPath [ networkmanager ]}
    '';
  }))
  (haskell.lib.compose.appendConfigureFlags (lib.optional werror "--ghc-options=-Werror"))
  haskell.lib.compose.justStaticExecutables
]
