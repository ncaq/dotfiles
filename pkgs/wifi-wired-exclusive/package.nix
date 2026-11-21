# 有線接続中はWiFiの接続を切り、有線が無くなったら繋ぎ直すNetworkManagerのdispatcherスクリプト。
#
# `nixos/native-linux/wifi-wired-exclusive.nix`から呼ばれる。
# 何をどう決めるかは`src/WifiWiredExclusive/Plan.hs`に書いてある。
{
  lib,
  haskell,
  localHaskellPackages,
  makeWrapper,
  networkmanager,
}:
let
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
  package = localHaskellPackages.callCabal2nix "wifi-wired-exclusive" source { };
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
  haskell.lib.compose.justStaticExecutables
]
