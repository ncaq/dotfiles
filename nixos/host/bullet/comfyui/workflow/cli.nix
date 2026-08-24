# 宣言したワークフローを`comfy-<名前>`のコマンドとして使えるようにする。
#
# 中身は`cli/main.py`で、何をどう変換しているかはその冒頭に書いてある。
#
# ワークフローが増えるたびに何かを書き足す必要は無い。
# `local.comfyui.workflows`を走査するので、
# `workflow/`へモジュールを1つ置けばコマンドも一緒に増える。
#
# ラッパーがPythonへ渡すのは、
# API形式ではなくUI形式のワークフローそのものである。
# API形式は`cli/convert.py`が実行時に組み立てる。
# 二重管理を作らないためで、
# UIで開くものとコマンドで投げるものが必ず同じ内容になる。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  jsonFormat = pkgs.formats.json { };

  # 動かすものだけをstoreへ入れる。
  # ディレクトリをそのまま渡すとテストまで付いてくる。
  source = lib.fileset.toSource {
    root = ./cli;
    fileset = lib.fileset.unions [
      ./cli/convert.py
      ./cli/dynamic.py
      ./cli/jsonutil.py
      ./cli/main.py
      ./cli/nodedef.py
      ./cli/params.py
    ];
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
      # `main.py`を直接指すと、
      # Pythonが置かれたディレクトリをsys.pathの先頭へ入れるので、
      # 隣のモジュールが素の名前で解決される。
      # 名前を別に渡す。
      # storeのファイル名は頭にハッシュが付くので、
      # パスからはワークフローの名前を取れない。
      exec ${pkgs.python3}/bin/python3 ${source}/main.py \
        ${name} ${jsonFormat.generate "${name}.json" workflow} "$@"
    '';
in
{
  # 標準ライブラリしか使わないので、
  # ComfyUIのPython環境ではなく素の`python3`で動く。
  environment.systemPackages = lib.mapAttrsToList mkCommand config.local.comfyui.workflows;
}
