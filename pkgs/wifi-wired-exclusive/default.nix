# 有線接続中はWiFiの接続を切り、有線が無くなったら繋ぎ直すNetworkManagerのdispatcherスクリプト。
# `nixos/native-linux/wifi-wired-exclusive.nix`から呼ばれます。
# 何をするかは`wifi-wired-exclusive.bash`の冒頭に書いてあります。
{
  lib,
  runCommand,
  makeWrapper,
  shellcheck,
  gnugrep,
  networkmanager,
}:
runCommand "wifi-wired-exclusive"
  {
    nativeBuildInputs = [
      makeWrapper
      shellcheck
    ];
    meta.mainProgram = "wifi-wired-exclusive";
  }
  ''
    shellcheck ${./wifi-wired-exclusive.bash}
    install -Dm755 ${./wifi-wired-exclusive.bash} \
      $out/libexec/wifi-wired-exclusive/wifi-wired-exclusive.bash
    # dispatcherのPATHにbashがあるとは限らないので、`env`で探させずストアのbashへ固定します。
    patchShebangs $out/libexec
    makeWrapper $out/libexec/wifi-wired-exclusive/wifi-wired-exclusive.bash \
      $out/bin/wifi-wired-exclusive \
      --prefix PATH : ${
        lib.makeBinPath [
          gnugrep
          networkmanager
        ]
      }
  ''
