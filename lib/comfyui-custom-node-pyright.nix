/**
  comfyuiCustomNodePyright: ComfyUIの自作カスタムノードをpyrightで型検査するためのderivation群。

  型: { pkgs, comfyui } -> { typecheckDir, check }

  引数:
    pkgs - pyrightとlinkFarmを取るためのnixpkgs
    comfyui - `pythonRuntime`と`comfyuiSrc`を持つcomfyui-nixのパッケージ

  戻り値:
    typecheckDir - pyrightがimport解決に使う`env`と`src`を並べたディレクトリ
    check - `pyrightconfig.json`をそのまま使ってpyrightを走らせるderivation

  なぜ必要か:
    自作カスタムノードは型アノテーションが書かれているのに型検査が無く、
    誤りはComfyUIがノードを読み込む時まで表面化しなかった。
    treefmtのruffは既定ルールのlintだけで型は見ない。

  import解決に何が要るか:
    `comfy`や`nodes`や`folder_paths`はPyPIには無く、
    ComfyUI本体のソースツリーの直下に置かれた素のモジュールなので、
    `comfyuiSrc`を`extraPaths`へ入れて解決させる。
    `torch`や`av`などのサードパーティは`pythonRuntime`が持っている。
    Nixのpython envは`bin/python`と`lib/pythonX.Y/site-packages`を備えていて、
    pyrightの`venvPath`と`venv`がそのまま使える形をしているため、
    venvを別に作る必要はない。

  なぜuvで型スタブを入れないか:
    `comfy`や`nodes`はPyPIに無く、torchのスタブはtorch本体に同梱されているので、
    結局PyPIからは揃わない。
    仮に揃えられてもcomfyui-nixが固定しているバージョンとの二重管理になり、
    実際に動く環境と型検査の見る環境がずれる。

  なぜコミットされた`pyrightconfig.json`を作業ディレクトリへ複製して使うか:
    設定をここで生成すると、
    エディタやコーディングエージェントが読む設定とCIの設定が別物になり、
    片方だけ通る状態を作ってしまう。
    リポジトリと同じ相対パスの並びを再現して同じ設定を読ませれば、
    このcheckが通ることがそのままエディタでも通ることを意味する。
*/
{ pkgs, comfyui }:
let
  # pyrightがリポジトリルートの`.typecheck`から相対パスで辿る2つをまとめる。
  # `venvPath`が`.typecheck`で`venv`が`env`、`extraPaths`が`.typecheck/src`に対応する。
  typecheckDir = pkgs.linkFarm "comfyui-typecheck" {
    env = comfyui.pythonRuntime;
    src = comfyui.comfyuiSrc;
  };
in
{
  inherit typecheckDir;

  check =
    pkgs.runCommand "comfyui-custom-node-pyright"
      {
        nativeBuildInputs = [ pkgs.pyright ];
      }
      ''
        # pyrightはキャッシュを$HOMEへ書こうとするので、ビルド用の一時領域へ向ける。
        export HOME="$TMPDIR"

        # リポジトリと同じ相対パスの並びを再現する。
        # ノードディレクトリ内の共有モジュールは`../share_encode.py`のようなsymlinkなので、
        # symlinkのまま複製すれば複製先でも同じように解決される。
        mkdir -p work/nixos/host/bullet/comfyui
        cp ${../pyrightconfig.json} work/pyrightconfig.json
        cp -r ${../nixos/host/bullet/comfyui/custom-node} work/nixos/host/bullet/comfyui/custom-node
        ln -s ${typecheckDir} work/.typecheck

        cd work
        # ファイル引数を渡すと`pyrightconfig.json`のincludeが上書きされるので引数なしで起動する。
        # `--warnings`で警告も失敗として扱い、import解決が中途半端な状態を通さない。
        pyright --warnings

        touch $out
      '';
}
