# ComfyUIのワークフローJSON(UI形式)をNix式から生成して、
# ComfyUIのuserディレクトリへシンボリックリンクで配置する。
#
# このディレクトリに`<ワークフロー名>.nix`を追加すると自動的に収集されて配置される。
# ワークフローファイルは`{ workflowLib }`を受け取り、
# JSONへ変換できるNixの値を返す関数として書く。
#
# 配置は`workflows/nix`をstoreのディレクトリへ丸ごとリンクする形にする。
# 中身が常にstoreの内容と完全一致するので、
# ワークフローの追加・リネーム・削除が自動で反映され、
# tmpfilesの個別リンクと違って古いファイルの手動削除が不要になる。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  dataDir = config.containers.comfyui.config.services.comfyui.dataDir;
  jsonFormat = pkgs.formats.json { };
  workflowLib = import ./lib.nix { inherit lib; };
  # ワークフロー定義ではないファイルは収集から除外する。
  excludeFiles = [
    "default.nix"
    "lib.nix"
  ];
  # 属性名がワークフロー名(ファイル名)になり、
  # 値はそのままJSONへ変換できるNixの値。
  workflows = lib.pipe (builtins.readDir ./.) [
    (lib.filterAttrs (
      name: type: type == "regular" && lib.hasSuffix ".nix" name && !(lib.elem name excludeFiles)
    ))
    (lib.mapAttrs' (
      name: _:
      lib.nameValuePair (lib.removeSuffix ".nix" name) (
        import (./. + "/${name}") { inherit workflowLib; }
      )
    ))
  ];
  workflowDir = pkgs.linkFarm "comfyui-workflows" (
    lib.mapAttrs' (
      name: workflow: lib.nameValuePair "${name}.json" (jsonFormat.generate "${name}.json" workflow)
    ) workflows
  );
in
{
  # `nix`ディレクトリはread-onlyのstoreへのリンクなので、
  # UIから上書き保存はできない。
  # 編集したものを残したい場合は`workflows/`直下などへ別名で保存する。
  systemd.tmpfiles.rules = [
    "d ${dataDir}/user 0755 comfyui comfyui - -"
    "d ${dataDir}/user/default 0755 comfyui comfyui - -"
    "d ${dataDir}/user/default/workflows 0755 comfyui comfyui - -"
    "L+ ${dataDir}/user/default/workflows/nix - - - - ${workflowDir}"
  ];
}
