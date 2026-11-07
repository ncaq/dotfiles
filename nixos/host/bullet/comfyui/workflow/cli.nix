# 宣言したワークフローを`comfy-<名前>`のコマンドとして使えるようにする。
#
# 中身は`pkgs/comfy-workflow`で、何をどう組み立てているかはそちらの`Cli.hs`の冒頭に書いてある。
# UI形式からAPI形式への変換と結果の待ち受けは公式の`comfy-cli`に任せていて、
# こちらが持つのはApp Modeの入力定義をフラグにする部分と、seedの配り方だけである。
#
# ワークフローが増えるたびに何かを書き足す必要は無い。
# `local.comfyui.workflows`を走査するので、
# `workflow/`へモジュールを1つ置けばコマンドも一緒に増える。
#
# ラッパーが渡すのは、
# API形式ではなくUI形式のワークフローそのものである。
# API形式は公式CLIが実行時に組み立てる。
# 二重管理を作らないためで、
# UIで開くものとコマンドで投げるものが必ず同じ内容になる。
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  jsonFormat = pkgs.formats.json { };

  comfy-cli = pkgs.callPackage ../../../../../pkgs/comfy-cli { };
  comfy-workflow = pkgs.callPackage ../../../../../pkgs/comfy-workflow {
    inherit comfy-cli;
    inherit (inputs) himari-src;
  };

  # 接続先。
  # ソケットアクティベーションのプロキシがホスト側で待ち受けているので、
  # コンテナのアドレスではなくループバックを指す。
  authority = "127.0.0.1:${toString config.containers.comfyui.config.services.comfyui.port}";

  mkCommand =
    name: workflow:
    pkgs.writeShellScriptBin "comfy-${name}" ''
      # 環境変数が既にあればそちらを優先する。
      # bullet以外から`COMFYUI_AUTHORITY=bullet:8188`で叩けるようにするため。
      export COMFYUI_AUTHORITY="''${COMFYUI_AUTHORITY:-${authority}}"
      export COMFYUI_OUTPUT_DIR="''${COMFYUI_OUTPUT_DIR:-${config.local.comfyui.outputDir}}"
      # 名前を別に渡す。
      # storeのファイル名は頭にハッシュが付くので、
      # パスからはワークフローの名前を取れない。
      exec ${lib.getExe comfy-workflow} ${name} ${jsonFormat.generate "${name}.json" workflow} "$@"
    '';
in
{
  environment.systemPackages = [
    # ワークフローを投げる以外の用途でも公式CLIを直接使えるようにしておく。
    comfy-cli
  ]
  ++ lib.mapAttrsToList mkCommand config.local.comfyui.workflows;
}
