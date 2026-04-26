# PRコメントにnvd diffを投稿するスクリプト。
{
  lib,
  runCommand,
  makeWrapper,
  shellcheck,
  coreutils,
  gh,
  git,
  jq,
  nix,
  nvd,
}:
runCommand "nvd-pr-diff"
  {
    nativeBuildInputs = [
      makeWrapper
      shellcheck
    ];
    meta.mainProgram = "nvd-pr-diff";
  }
  ''
    shellcheck ${./nvd-pr-diff.sh}
    install -Dm755 ${./nvd-pr-diff.sh} $out/libexec/nvd-pr-diff/nvd-pr-diff.sh
    makeWrapper $out/libexec/nvd-pr-diff/nvd-pr-diff.sh $out/bin/nvd-pr-diff \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          gh
          git
          jq
          nix
          nvd
        ]
      }
  ''
