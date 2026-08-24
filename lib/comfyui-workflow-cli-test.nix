/**
  comfyuiWorkflowCliTest: ワークフローを名前で呼ぶコマンドのpytestを走らせるderivation。

  型: { pkgs } -> derivation

  引数:
    pkgs - pytestを走らせるPythonと`runCommand`を取るためのnixpkgs

  何を検査するか:
    `nodedef.py`のノード定義の読み取りと、
    `convert.py`のUI形式からAPI形式への変換と、
    `params.py`のフラグ名の決め方と、
    `dynamic.py`の`{a|b|c}`の展開と、
    `main.py`が持つ外部I/Oを踏まない判断を対象にする。

    どれも実機で確かめにくい。
    変換の結果が1つずれていても、
    ComfyUIはstepsの位置にcfgの値が入ったまま実行してしまうので、
    画像は出るが内容だけが違うという形で壊れる。
    フラグ名の決め方は`--help`に出るものの、
    どういう時にウィジェット名から離れるのかは、
    ワークフローを1つ見ても読み取れない。

    `main.py`はHTTPと`argparse`と待ちの繰り返しが本体だが、
    その中に混ざる判断だけは対象にする。
    値の解釈と、履歴から保存されたファイルを拾う部分がそれで、
    どちらも外部I/Oを踏まないのでimportして呼べる。
    後者は間違えても例外にならず、
    表示されるパスが違うだけの壊れ方をする。

    HTTPを踏む関数と`main`自体は対象にしない。

  なぜComfyUIのPython環境を使わないか:
    `lib/comfyui-idle-free-memory-test.nix`と同じ理由による。
    対象が標準ライブラリしか使わないので、
    素の`python3`で足りるなら、
    CUDA版torchを含む閉包を持たないaarch64でもそのまま走らせられる。
*/
{ pkgs }:
let
  inherit (pkgs) lib;

  cli = ../nixos/host/bullet/comfyui/workflow/cli;

  source = lib.fileset.toSource {
    root = cli;
    fileset = lib.fileset.unions [
      (cli + "/tests")
      (cli + "/convert.py")
      (cli + "/dynamic.py")
      (cli + "/jsonutil.py")
      (cli + "/main.py")
      (cli + "/nodedef.py")
      (cli + "/params.py")
    ];
  };

  python = pkgs.python3.withPackages (pythonPkgs: [ pythonPkgs.pytest ]);
in
pkgs.runCommand "comfyui-workflow-cli-test"
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
