# ComfyUIのワークフローを宣言するオプションと、
# ComfyUIのuserディレクトリへの配置。
# 各ワークフローは同ディレクトリのモジュールが`local.comfyui.workflows.<名前>`で宣言する。
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
  workflowDir = pkgs.linkFarm "comfyui-workflows" (
    lib.mapAttrs' (
      name: workflow: lib.nameValuePair "${name}.json" (jsonFormat.generate "${name}.json" workflow)
    ) config.local.comfyui.workflows
  );
in
{
  options.local.comfyui.workflows = lib.mkOption {
    type = lib.types.attrsOf jsonFormat.type;
    default = { };
    description = ''
      ComfyUIへ配置するワークフロー。
      属性名がワークフロー名(ファイル名)になり、
      値はUI形式のJSONへ変換できるNixの値。
    '';
  };
  # `nix`ディレクトリはread-onlyのstoreへのリンクなので、
  # UIから上書き保存はできない。
  # 編集したものを残したい場合は`workflows/`直下などへ別名で保存する。
  config.systemd.tmpfiles.rules = [
    "d ${dataDir}/user 0755 comfyui comfyui - -"
    "d ${dataDir}/user/default 0755 comfyui comfyui - -"
    "d ${dataDir}/user/default/workflows 0755 comfyui comfyui - -"
    "L+ ${dataDir}/user/default/workflows/nix - - - - ${workflowDir}"
  ];
}
