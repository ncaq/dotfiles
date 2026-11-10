# GarageのS3バケットとキーを用意するコマンド。
# `lib/garage-setup.nix`が作るサービスから呼ばれます。
# 何をするかと必要な環境変数は`garage-setup.bash`の冒頭に書いてあります。
{
  lib,
  runCommand,
  makeWrapper,
  shellcheck,
  coreutils,
  curl,
  jq,
}:
runCommand "garage-setup"
  {
    nativeBuildInputs = [
      makeWrapper
      shellcheck
    ];
    meta.mainProgram = "garage-setup";
  }
  ''
    shellcheck ${./garage-setup.bash}
    install -Dm755 ${./garage-setup.bash} $out/libexec/garage-setup/garage-setup.bash
    # systemdのサービスのPATHにはbashが無いので、`env`で探させずストアのbashへ固定します。
    patchShebangs $out/libexec
    makeWrapper $out/libexec/garage-setup/garage-setup.bash $out/bin/garage-setup \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          curl
          jq
        ]
      }
  ''
