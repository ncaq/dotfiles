# bulletのComfyUIワークフローの`lib/`の各モジュールを、テストから読むためにまとめたもの。
# テストのファイルごとに深い相対パスを書かずに済むよう、パスはここ1か所に置く。
{ lib }:
let
  workflowLib = ../../../nixos/host/bullet/comfyui/workflow/lib;
  load = name: import (workflowLib + "/${name}.nix") { inherit lib; };
in
lib.genAttrs [
  "builder"
  "duplicate"
  "link"
  "order"
  "overlap"
  "widget"
] load
