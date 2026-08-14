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
    リポジトリ内の全てのPythonファイル。
    `pyrightconfig.json`の`include`は`.`で、
    検査しないものを`exclude`で挙げる形にしている。

    検査する場所を`include`へ並べる形だと、
    新しくPythonを置いた時に足し忘れると黙って未検査になる。
    実際に`pkgs/safetensors-fp16`が長らく検査対象外だった。
    pyrightは`include`の外を認識しないのでこの漏れを報告できないため、
    そもそも漏れようがない形にする。

  なぜ`exclude`に既定値を書き直すか:
    pyrightの`exclude`の既定値は、
    `node_modules`と`__pycache__`と、
    ドットで始まる名前を落とす3つのglobになっている。
    `exclude`を書くとこの既定値ごと上書きされるので、
    落としたいものを1つ足すだけでも全部書き直す必要がある。
    ドットで始まる名前が落ちなくなると`.direnv`の中まで走査してしまい、
    検査が終わらなくなる。

    `result*`は`nix build`のout-linkで、
    Nix storeのシステム閉包を指している。
    pyrightは`.gitignore`を見ないので、
    ここを明示しないとstore内のPythonを数千ファイル検査してしまう。

  なぜ必要か:
    型アノテーションが書かれているのに型検査が無かった。
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
    テストはさらに`pytest`と、
    リファレンス実装としての`safetensors`を使う。
    `numpy`と`tqdm`はComfyUIの環境が既に持っているのでそのまま解決できる。
    残りを`withExtraPythonPackages`で足せば環境を分けずに済む。
    環境が1つなら`venvPath`と`venv`が1組で済み、
    Pythonのバージョン文字列をコミットするファイルへ書かずに済む。

    `safetensors`はComfyUI本体も依存しているので足さなくても解決するが、
    それはcomfyui-nix側の都合であって、
    `pkgs/safetensors-fp16/default.nix`の`nativeCheckInputs`とは無関係である。
    上流の依存が変われば`reportMissingImports`で落ちて原因が分かりにくくなるため、
    このリポジトリが必要とするものは明示する。

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

  なぜ`strict`にして例外をファイル側へ置くか:
    `standard`は`dict`の型引数の書き忘れも、
    値の型が不明なまま流れていることも報告しない。
    型を書いているつもりで効いていない場所が生まれるので`strict`を採る。

    ただし`strict`の`reportUnknown*`系は、
    型注釈を持たないComfyUI本体や、
    注釈の埋まっていないスタブしか持たない外部ライブラリに触れる式を全て挙げてしまう。
    これは自分のコードを直しても消えない。

    設定側でこの3ルールを落とすと、
    自分のコードの型が失われている箇所まで一緒に見逃す。
    実際、JSONを`isinstance`だけで受けていた`translate-text`と`safetensors-fp16`は、
    `strict`にして初めて要素の型が不明なまま流れていると分かった。

    そのため設定は`strict`のままにして、
    外部の型が無いことが原因だと1件ずつ確認できたファイルにだけ、
    ファイル先頭の`# pyright:`コメントで理由付きで落とす。
    どのファイルで落としているかは、
    増減のたびにここを直すことになるので書かない。
    `# pyright:`をgrepすれば分かる。

  なぜ`strict`にも入っていないルールを足すか:
    pyrightには`strict`でも既定でオフのルールがある。
    そのうち現状のコードで指摘が出ないものを有効にしておく。
    今は無料で、後から書くコードだけが引っ掛かる。

    特に`reportUnnecessaryTypeIgnoreComment`は、
    要らなくなった`# pyright: ignore`を報告する。
    抑制はどれも上流の型の不足が理由なので、
    上流に型が付いた時に外し忘れずに済む。

  なぜコミットされた`pyrightconfig.json`を作業ディレクトリへ複製して使うか:
    設定をここで生成すると、
    エディタやコーディングエージェントが読む設定とCIの設定が別物になり、
    片方だけ通る状態を作ってしまう。
    リポジトリと同じ相対パスの並びを再現して同じ設定を読ませれば、
    このcheckが通ることがそのままエディタでも通ることを意味する。
*/
{ pkgs, comfyui }:
let
  inherit (pkgs) lib;

  # 検査対象はリポジトリ内の全Pythonファイル。
  # `pyrightconfig.json`の`include`が`.`なので、
  # ここも同じく全部を渡さないとエディタとCIで見る範囲がずれる。
  # Pythonと設定ファイルだけに絞ることで、
  # 無関係なファイルの変更でこのcheckが作り直されないようにする。
  #
  # `.pyi`はスタブを自作した場合にimport解決へ影響するので、
  # `include`を`.`にして漏れようがなくしたのと同じ理由で最初から拾っておく。
  # `typings/`ディレクトリや`py.typed`のような、
  # ここに挙がっていない種類のファイルを置く時はこのfilesetにも足すこと。
  source = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../pyrightconfig.json
      (lib.fileset.fileFilter (file: file.hasExt "py" || file.hasExt "pyi") ../.)
    ];
  };

  # pyrightがリポジトリルートの`.typecheck`から相対パスで辿る2つをまとめる。
  # `venvPath`が`.typecheck`で`venv`が`env`、`extraPaths`が`.typecheck/src`に対応する。
  typecheckDir = pkgs.linkFarm "typecheck" {
    env =
      (comfyui.withExtraPythonPackages (pythonPkgs: [
        pythonPkgs.pytest
        pythonPkgs.safetensors
      ])).pythonRuntime;
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
        cp -r ${source} work
        chmod -R u+w work
        ln -s ${typecheckDir} work/.typecheck

        cd work
        # ファイル引数を渡すと`pyrightconfig.json`のincludeが上書きされるので引数なしで起動する。
        # `--warnings`で警告も失敗として扱い、import解決が中途半端な状態を通さない。
        pyright --warnings

        touch $out
      '';
}
