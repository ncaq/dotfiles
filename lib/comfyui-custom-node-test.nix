/**
  comfyuiCustomNodeTest: ComfyUIの自作カスタムノードのpytestを走らせるderivation。

  型: { pkgs } -> derivation

  引数:
    pkgs - pytestを走らせるPythonと`runCommand`を取るためのnixpkgs

  何を検査するか:
    ComfyUI本体やtorchに触れないモジュールだけを対象にする。
    ノードの`__init__.py`はそれらをimportするので、
    読み込むだけでGPUを持つ実行環境が要り、テストからは触れない。
    検査したい処理はモジュールへ分けておく。

    今の対象は共有モジュールの`translate.py`と、
    anime-video-quickの`manifest.py`である。
    どちらも壊れた入力を受けた時の分岐が本体で、
    翻訳のレスポンスも中断したジョブの記録も、
    実際に壊れたものが来る経路でしか通らない。

  なぜComfyUIのPython環境を使わないか:
    `checks.pyright`はComfyUIの環境を使うが、
    こちらの対象は標準ライブラリと`requests`しか使わない。
    素の`python3`で足りるなら、
    CUDA版torchを含む閉包を持たないaarch64でもそのまま走らせられる。

  なぜノードのderivationと入力を分けるか:
    `writeCheckedNode`はノードごとに入力を絞っているので、
    ここでも読むファイルだけを`fileset`へ並べる。
    ノードのディレクトリ全体を入力にすると、
    テストが読まないファイルの変更でもこのcheckが作り直される。
*/
{ pkgs }:
let
  inherit (pkgs) lib;

  customNode = ../nixos/host/bullet/comfyui/custom-node;

  source = lib.fileset.toSource {
    root = customNode;
    fileset = lib.fileset.unions [
      (customNode + "/tests")
      (customNode + "/translate.py")
      (customNode + "/anime-video-quick/manifest.py")
    ];
  };

  python = pkgs.python3.withPackages (pythonPkgs: [
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
