# PRコメントにnvd diffを投稿するスクリプト。
# スクリプト本体(nvd-pr-diff.sh)と、
# awkフォーマット整形(format-for-markdown.awk)を、
# 同一ディレクトリにインストールし、
# 実行時に相対パスで参照します。
{
  lib,
  runCommand,
  makeWrapper,
  shellcheck,
  coreutils,
  gawk,
  gh,
  git,
  jq,
  nix,
  nvd,
}:
let
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./format-for-markdown.awk
      ./nvd-pr-diff.sh
    ];
  };
in
runCommand "nvd-pr-diff"
  {
    nativeBuildInputs = [
      makeWrapper
      shellcheck
    ];
    meta.mainProgram = "nvd-pr-diff";
  }
  ''
    shellcheck ${src}/nvd-pr-diff.sh
    gawk --lint=fatal -f ${src}/format-for-markdown.awk </dev/null >/dev/null
    install -Dm755 ${src}/nvd-pr-diff.sh $out/libexec/nvd-pr-diff/nvd-pr-diff.sh
    install -Dm644 ${src}/format-for-markdown.awk $out/libexec/nvd-pr-diff/format-for-markdown.awk
    makeWrapper $out/libexec/nvd-pr-diff/nvd-pr-diff.sh $out/bin/nvd-pr-diff \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          gawk
          gh
          git
          jq
          nix
          nvd
        ]
      }
  ''
