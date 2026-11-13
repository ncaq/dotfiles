# 保存ノードの`filename_prefix`の形式を検証する。
# 置換パターンはサーバ側のfolder_pathsの仕様に合わせている。
{ lib }:
let
  builder = import ../../../../nixos/host/bullet/comfyui/workflow/lib/builder.nix { inherit lib; };
in
assert lib.assertMsg (
  builder.mkFilenamePrefix "test" == "test/test-%year%-%month%-%day%-%hour%-%minute%-%second%"
) "filename_prefixの形式が想定と違います";
assert lib.assertMsg (
  builder.mkFilenamePrefixWith "test" "-x"
  == "test/test-x-%year%-%month%-%day%-%hour%-%minute%-%second%"
) "サフィックス付きfilename_prefixの形式が想定と違います";
true
