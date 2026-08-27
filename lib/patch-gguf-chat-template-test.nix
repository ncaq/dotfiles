/**
  patchGgufChatTemplateTest: GGUFのチャットテンプレートの出し入れのpytestを走らせるderivation。

  型: { pkgs } -> derivation

  引数:
    pkgs - pytestを走らせるPythonと`runCommand`を取るためのnixpkgs

  何を検査するか:
    `patch_gguf_chat_template.py`のGGUFのメタデータの走査と、
    バイト長を保ったままの書き戻しを対象にする。

    このスクリプトは22GB級のGGUFをin-placeで書き換えるので、
    オフセットを1バイトでも間違えると隣のメタデータやテンソルを壊すが、
    壊れたGGUFはロードするまで表面化しない。
    実物で試すには重すぎるため、
    同じ構造を持つ小さなGGUFをテスト側で組み立てて検査する。

    差分の当たり方は対象にしない。
    それは`patch`コマンドの仕事で、
    コンテキスト行が合わなければビルドが失敗する形になっている。
*/
{ pkgs }:
let
  inherit (pkgs) lib;

  source = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./tests
      ./patch_gguf_chat_template.py
    ];
  };

  python = pkgs.python3.withPackages (pythonPkgs: [ pythonPkgs.pytest ]);
in
pkgs.runCommand "patch-gguf-chat-template-test"
  {
    nativeBuildInputs = [ python ];
  }
  ''
    # pytestはキャッシュを書くので、読み取り専用のstoreから作業領域へ複製する。
    cp -r ${source} work
    chmod -R u+w work
    cd work

    # 実機ではNixの`runCommand`からスクリプトとして起動される。
    # `tests/conftest.py`がその時と同じ並びをsys.pathで再現する。
    pytest tests

    touch $out
  ''
