# seminarへのレイテンシを見てTailscaleのexit nodeを切り替えるNetworkManagerのdispatcherスクリプト。
#
# `nixos/laptop/tailscale-exit-node.nix`から呼ばれる。
# 何をどう決めるかは`src/TailscaleExitNode/ExitNode.hs`に書いてある。
{
  lib,
  haskell,
  localHaskellPackages,
  makeWrapper,
  tailscale,
}:
let
  # 動かすものだけをstoreへ入れる。
  # ディレクトリをそのまま渡すと`dist-newstyle`のような作業中のファイルまで付いてくる。
  source = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./tailscale-exit-node.cabal
      ./app
      ./src
      ./test
    ];
  };
  package = localHaskellPackages.callCabal2nix "tailscale-exit-node" source { };
in
lib.pipe package [
  (haskell.lib.compose.overrideCabal (old: {
    buildTools = (old.buildTools or [ ]) ++ [ makeWrapper ];
    # レイテンシの計測とexit nodeの設定は`tailscale`に任せるので、PATHへ足して包む。
    postInstall = (old.postInstall or "") + ''
      wrapProgram "$out/bin/tailscale-exit-node" \
        --prefix PATH : ${lib.makeBinPath [ tailscale ]}
    '';
  }))
  haskell.lib.compose.justStaticExecutables
]
