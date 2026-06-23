# `secrets/cachix.yaml`から認証トークンを復号して、
# `cachix push ncaq`を実行するラッパー。
{
  lib,
  runCommand,
  makeWrapper,
  shellcheck,
  cachix,
  coreutils,
  sops,
}:
runCommand "cachix-push-ncaq"
  {
    nativeBuildInputs = [
      makeWrapper
      shellcheck
    ];
    meta.mainProgram = "cachix-push-ncaq";
  }
  ''
    shellcheck ${./cachix-push-ncaq.bash}
    install -Dm755 ${./cachix-push-ncaq.bash} $out/libexec/cachix-push-ncaq/cachix-push-ncaq.bash
    makeWrapper $out/libexec/cachix-push-ncaq/cachix-push-ncaq.bash $out/bin/cachix-push-ncaq \
      --prefix PATH : ${
        lib.makeBinPath [
          cachix
          coreutils
          sops
        ]
      }
  ''
