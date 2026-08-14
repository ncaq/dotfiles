/**
  pythonPyright: リポジトリ内のPythonをpyrightで型検査するためのderivation群。

  型: { pkgs, comfyui } -> { typecheckDir, check }

  引数:
    pkgs - pyrightとlinkFarmを取るためのnixpkgs
    comfyui - `pythonRuntime`と`comfyuiSrc`と`withExtraPythonPackages`を持つcomfyui-nixのパッケージ

  戻り値:
    typecheckDir - pyrightがimport解決に使う`env`と`src`を並べたディレクトリ
    check - `pyrightconfig.json`をそのまま使ってpyrightを走らせるderivation

  検査する対象:
    `nixos/host/bullet/comfyui/custom-node`のComfyUI自作カスタムノードと、
    `pkgs/safetensors-fp16`。
    どちらを検査するかは`pyrightconfig.json`の`include`が決める。

  なぜ必要か:
    どちらも型アノテーションが書かれているのに型検査が無かった。
    カスタムノードの誤りはComfyUIがノードを読み込む時まで表面化せず、
    treefmtのruffは既定ルールのlintだけで型は見ない。

  import解決に何が要るか:
    `comfy`や`nodes`や`folder_paths`はPyPIには無く、
    ComfyUI本体のソースツリーの直下に置かれた素のモジュールなので、
    `comfyuiSrc`を`extraPaths`へ入れて解決させる。
    `torch`や`av`などのサードパーティは`pythonRuntime`が持っている。
    Nixのpython envは`bin/python`と`lib/pythonX.Y/site-packages`を備えていて、
    pyrightの`venvPath`と`venv`がそのまま使える形をしているため、
    venvを別に作る必要はない。

  なぜsafetensors-fp16も同じ環境で検査するか:
    このパッケージの依存は`numpy`と`tqdm`で、
    どちらもComfyUIの環境が既に持っている。
    足りないのはテストが使う`pytest`だけなので、
    環境を分けずに`withExtraPythonPackages`で足す。
    環境が1つなら`venvPath`と`venv`が1組で済み、
    Pythonのバージョン文字列をコミットするファイルへ書かずに済む。

    `numpy`と`tqdm`はcomfyui-nixが固定したバージョンで検査されることになるが、
    `pkgs/safetensors-fp16/pyproject.toml`の`requires-python`が`>=3.12`で、
    ComfyUIの環境も3.12なので下限で検査する形になる。
    バージョン差で見逃した誤りは`checks.safetensors-fp16`の実際のビルドとテストが拾う。

  なぜuvやuv2nixで依存を用意しないか:
    uv2nixは`uv.lock`のPyPI依存をNixへ持ち込むためのものだが、
    `pkgs/safetensors-fp16/default.nix`が依存を既に宣言しているので二重管理になる。
    ComfyUI側はそもそも`comfy`や`nodes`がPyPIに無く、
    torchのスタブはtorch本体に同梱されているため、
    PyPIからは揃わない。
    どちらも実際に動く環境と型検査の見る環境がずれる方が困る。

  なぜ`reportMissingTypeArgument`だけ`standard`へ足すか:
    `dict`のように型引数を書かずに使える総称型は、
    書き忘れても`standard`では何も言われず、
    要素の型が失われたまま検査を通ってしまう。
    型を書いているつもりで効いていない場所が生まれるので、
    `strict`のこのルールだけ持ち上げる。
    `strict`そのものは`reportUnknown*`系が、
    型注釈を持たないComfyUI本体に起因して大量に出るため採らない。

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
  typecheckDir = pkgs.linkFarm "typecheck" {
    env = (comfyui.withExtraPythonPackages (pythonPkgs: [ pythonPkgs.pytest ])).pythonRuntime;
    src = comfyui.comfyuiSrc;
  };
in
{
  inherit typecheckDir;

  check =
    pkgs.runCommand "pyright"
      {
        nativeBuildInputs = [ pkgs.pyright ];
      }
      ''
        # pyrightはキャッシュを$HOMEへ書こうとするので、ビルド用の一時領域へ向ける。
        export HOME="$TMPDIR"

        # リポジトリと同じ相対パスの並びを再現する。
        # `pyrightconfig.json`の`include`と`executionEnvironments`が相対パスで書かれていて、
        # そのまま解決できる必要がある。
        # カスタムノードの共有モジュールは`../share_encode.py`のようなsymlinkなので、
        # symlinkのまま複製すれば複製先でも同じように解決される。
        mkdir -p work/nixos/host/bullet/comfyui work/pkgs
        cp ${../pyrightconfig.json} work/pyrightconfig.json
        cp -r ${../nixos/host/bullet/comfyui/custom-node} work/nixos/host/bullet/comfyui/custom-node
        cp -r ${../pkgs/safetensors-fp16} work/pkgs/safetensors-fp16
        ln -s ${typecheckDir} work/.typecheck

        cd work
        # ファイル引数を渡すと`pyrightconfig.json`のincludeが上書きされるので引数なしで起動する。
        # `--warnings`で警告も失敗として扱い、import解決が中途半端な状態を通さない。
        pyright --warnings

        touch $out
      '';
}
