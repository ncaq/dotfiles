# flakeに定義された全ホストの閉包をGC rootとして登録するコマンド。
# 何をどう登録するかは`nix-gc-root-hosts.bash`の冒頭に書いてあります。
{
  lib,
  runCommand,
  makeWrapper,
  shellcheck,
  coreutils,
  jq,
  nix,
}:
runCommand "nix-gc-root-hosts"
  {
    nativeBuildInputs = [
      makeWrapper
      shellcheck
    ];
    meta.mainProgram = "nix-gc-root-hosts";
  }
  ''
    shellcheck ${./nix-gc-root-hosts.bash}
    install -Dm755 ${./nix-gc-root-hosts.bash} $out/libexec/nix-gc-root-hosts/nix-gc-root-hosts.bash
    # systemdのサービスのPATHにはbashが無いので、`env`で探させずストアのbashへ固定します。
    patchShebangs $out/libexec
    makeWrapper $out/libexec/nix-gc-root-hosts/nix-gc-root-hosts.bash $out/bin/nix-gc-root-hosts \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          jq
          nix
        ]
      }
  ''
