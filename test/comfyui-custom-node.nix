/**
  comfyuiCustomNodeTest: ComfyUIの自作カスタムノードのpytestを走らせるderivation。

  型: { pkgs, comfyui } -> derivation

  引数:
    pkgs - `runCommand`と`fileset`を取るためのnixpkgs
    comfyui - Pythonインタプリタとパッケージセットを取るためのComfyUIのパッケージ

  何を検査するか:
    ComfyUI本体やtorchに触れないモジュールだけを対象にする。
    ノードの`__init__.py`はそれらをimportするので、
    読み込むだけでGPUを持つ実行環境が要り、テストからは触れない。
    検査したい処理はモジュールへ分けておく。

    今の対象は共有モジュールの`translate.py`、
    anime-video-quickの`manifest.py`、
    rewrite-edit-promptの`rewrite.py`である。
    翻訳と記録と書き換えはどれも壊れた入力を受けた時の分岐が本体で、
    翻訳のレスポンスも中断したジョブの記録も途中で切れた生成も、
    実際に壊れたものが来る経路でしか通らない。

  なぜComfyUIのPythonインタプリタを使うか:
    テストの対象は実際にはComfyUIのPython環境で動くので、
    nixpkgsの既定の`python3`で走らせるとバージョンがずれ、
    ComfyUIのPythonに無い構文や挙動に依存してもテストで気づけない。
    `checks.pyright`もComfyUIの環境を使うので、
    型検査とテストが同じバージョンを見るように揃える。

  なぜComfyUIの環境そのものは使わないか:
    対象は標準ライブラリと`requests`しか使わないので、
    `pythonRuntime`からインタプリタとパッケージセットだけを取り、
    `pytest`と`requests`を足す。
    torchなどを閉包に含めずに済む。

  なぜノードのderivationと入力を分けるか:
    `writeCheckedNode`はノードごとに入力を絞っているので、
    ここでも読むファイルだけを`fileset`へ並べる。
    ノードのディレクトリ全体を入力にすると、
    テストが読まないファイルの変更でもこのcheckが作り直される。
*/
{ pkgs, comfyui }:
let
  inherit (pkgs) lib;

  customNode = ../nixos/host/bullet/comfyui/custom-node;

  source = lib.fileset.toSource {
    root = customNode;
    fileset = lib.fileset.unions [
      (customNode + "/tests")
      (customNode + "/translate.py")
      (customNode + "/anime-video-quick/manifest.py")
      (customNode + "/rewrite-edit-prompt/rewrite.py")
    ];
  };

  python = comfyui.pythonRuntime.python.withPackages (pythonPkgs: [
    pythonPkgs.pytest
    pythonPkgs.requests
  ]);
in
pkgs.runCommand "comfyui-custom-node-test"
  {
    nativeBuildInputs = [ python ];
  }
  ''
    # pytestはキャッシュを書くので、読み取り専用のstoreから作業領域へ複製する。
    cp -r ${source} work
    chmod -R u+w work
    cd work

    # ComfyUIが読む配置をそのまま再現して、
    # `tests/conftest.py`がsys.pathを組み立てる。
    pytest tests

    touch $out
  ''
