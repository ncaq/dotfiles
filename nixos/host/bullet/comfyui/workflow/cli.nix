# 宣言したワークフローを`comfy-<名前>`のコマンドとして使えるようにする。
#
# 中身は`pkgs/comfy-workflow`で、何をどう組み立てているかはそちらの`Cli.hs`の冒頭に書いてある。
# UI形式からAPI形式への変換と結果の待ち受けは公式の`comfy-cli`に任せていて、
# こちらが持つのはApp Modeの入力定義をフラグにする部分と、seedの配り方と、`POST /prompt`へ投げる部分だけである。
#
# ワークフローが増えるたびに何かを書き足す必要は無い。
# `local.comfyui.workflows`を走査するので、
# `workflow/`へモジュールを1つ置けばコマンドも一緒に増える。
#
# ラッパの作り方は`pkgs/comfy-workflow`の`mkCommand`にあり、
# ここが決めるのは接続先と出力先だけである。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs) comfy-cli comfy-workflow;

  # 接続先。
  # ソケットアクティベーションのプロキシがホスト側で待ち受けているので、
  # コンテナのアドレスではなくループバックを指す。
  authority = "[::1]:${toString config.containers.comfyui.config.services.comfyui.port}";

  mkCommand =
    name: workflow:
    comfy-workflow.mkCommand {
      inherit name workflow authority;
      inherit (config.local.comfyui) outputDir;
    };
in
{
  environment.systemPackages = [
    # ワークフローを投げる以外の用途でも公式CLIを直接使えるようにしておく。
    comfy-cli
  ]
  ++ lib.mapAttrsToList mkCommand config.local.comfyui.workflows;
}
