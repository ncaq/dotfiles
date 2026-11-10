# seminarへのレイテンシを見てTailscaleのexit nodeを切り替えるNetworkManagerのdispatcherスクリプト。
# `nixos/laptop/tailscale-exit-node.nix`から呼ばれます。
# 何をするかは`tailscale-exit-node.bash`の冒頭に書いてあります。
{
  lib,
  runCommand,
  makeWrapper,
  shellcheck,
  bash,
  coreutils,
  gnugrep,
  tailscale,
}:
runCommand "tailscale-exit-node"
  {
    nativeBuildInputs = [
      makeWrapper
      shellcheck
    ];
    meta.mainProgram = "tailscale-exit-node";
  }
  ''
    shellcheck ${./tailscale-exit-node.bash}
    install -Dm755 ${./tailscale-exit-node.bash} \
      $out/libexec/tailscale-exit-node/tailscale-exit-node.bash
    # dispatcherのPATHにbashがあるとは限らないので、`env`で探させずストアのbashへ固定します。
    patchShebangs $out/libexec
    makeWrapper $out/libexec/tailscale-exit-node/tailscale-exit-node.bash \
      $out/bin/tailscale-exit-node \
      --prefix PATH : ${
        lib.makeBinPath [
          # スクリプトの中で`bash -c`を呼ぶために要る。
          bash
          coreutils
          gnugrep
          tailscale
        ]
      }
  ''
