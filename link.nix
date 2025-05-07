# `linked`に存在するファイル全てに対してシンボリックリンクを作成する。
{ config, lib, ... }:
let
  baseDir = ./linked;

  # 再帰的にファイルだけを取得。
  files = lib.filesystem.listFilesRecursive baseDir;

  # baseDirからの相対パスを作るユーティリティ。
  relPath =
    absPath:
    let
      absStr = toString absPath;
      baseStr = "${toString baseDir}/";
    in
    lib.removePrefix baseStr absStr;

  # `home.file` 用の1要素を生成。
  mkPair =
    absPath:
    lib.nameValuePair (relPath absPath) {
      source = config.lib.file.mkOutOfStoreSymlink absPath;
    };

  homeFileAttrs = builtins.listToAttrs (map mkPair files);
in
{
  home.file = homeFileAttrs;
}
