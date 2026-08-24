/**
  comfyuiIdleFreeMemoryTest: アイドル解放の常駐プロセスのpytestを走らせるderivation。

  型: { pkgs } -> derivation

  引数:
    pkgs - pytestを走らせるPythonと`runCommand`を取るためのnixpkgs

  何を検査するか:
    `response.py`のComfyUIの応答の解釈と、
    `state.py`のアイドルの判定だけを対象にする。
    `main.py`は環境変数とHTTPと`while True`を持つので、
    ここからは触らない。

    解釈の方は正常系より異常系が本体である。
    ComfyUIのAPIには型が無く、
    バージョンが上がって形が変わった時に、
    例外ではなく静かに違う値が返る形で壊れる。
    実機で1回動かしても通るのは1本の経路だけなので、
    壊れた形を並べて分岐を固定する。

    判定の方は順序と境界が本体である。
    「確認の隙間に終わった生成を拾い直す」
    「解放済みなら投げ直さない」
    「しきい値を跨いだ最初の周回でだけ解放する」
    が同時に成り立つ必要があり、
    どれか1つを崩しても1周回が数分かかる実機では滅多に表面化しない。

  なぜComfyUIのPython環境を使わないか:
    `lib/comfyui-custom-node-test.nix`と同じ理由による。
    対象が標準ライブラリしか使わないので、
    素の`python3`で足りるなら、
    CUDA版torchを含む閉包を持たないaarch64でもそのまま走らせられる。

  なぜ`main.py`を入力へ入れないか:
    テストが読まないファイルの変更でこのcheckが作り直されるのを避ける。
    `main.py`の側は`checks.pyright`が見る。
*/
{ pkgs }:
let
  inherit (pkgs) lib;

  idleFreeMemory = ../nixos/host/bullet/comfyui/idle-free-memory;

  source = lib.fileset.toSource {
    root = idleFreeMemory;
    fileset = lib.fileset.unions [
      (idleFreeMemory + "/tests")
      (idleFreeMemory + "/response.py")
      (idleFreeMemory + "/state.py")
    ];
  };

  python = pkgs.python3.withPackages (pythonPkgs: [ pythonPkgs.pytest ]);
in
pkgs.runCommand "comfyui-idle-free-memory-test"
  {
    nativeBuildInputs = [ python ];
  }
  ''
    # pytestはキャッシュを書くので、読み取り専用のstoreから作業領域へ複製する。
    cp -r ${source} work
    chmod -R u+w work
    cd work

    # 実機では`main.py`と同じディレクトリに置かれた素のモジュールとして解決される。
    # `tests/conftest.py`がその並びをsys.pathで再現する。
    pytest tests

    touch $out
  ''
