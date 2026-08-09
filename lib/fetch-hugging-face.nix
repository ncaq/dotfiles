# Hugging Faceのcommit固定URLからファイルを取得する共通関数。
{ pkgs }:
{
  owner,
  repo,
  rev,
  file,
  hash,
}:
pkgs.fetchurl {
  name = builtins.baseNameOf file;
  url = "https://huggingface.co/${owner}/${repo}/resolve/${rev}/${file}";
  inherit hash;
}
