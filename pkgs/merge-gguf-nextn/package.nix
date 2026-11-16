# GGUFの本体へ、別ファイルで配られたMTPのNextN層を足すコマンド。
#
# `lib/quantize-gguf-with-nextn.nix`がモデルの量子化derivationから呼ぶ。
# なぜまとめる必要があるのかと、どうまとめるのかは`src/merge_gguf_nextn/merge.py`の冒頭に書いてある。
#
# Pythonで書いているのは、GGUFの上流の実装がllama.cppに同梱されたgguf-pyだからである。
# llama.cppの変換スクリプトもgguf-pyで書き出しているので、
# 同じライブラリで読み書きすればメタデータの型や整列の扱いで食い違いが起きにくい。
# 補助プログラムの言語の基準では、問題を手っ取り早く解決できるライブラリがある場合に当たる。
# `pkgs/patch-gguf-chat-template`がHaskellなのは、
# 長さを変えずにメタデータの文字列を1つ書き換えるだけで、
# GGUFの書き出しまでは要らないためである。
{
  lib,
  python3Packages,
}:
python3Packages.buildPythonApplication {
  pname = "merge-gguf-nextn";
  version = "0.1.0";
  pyproject = true;

  # 動かすものだけをstoreへ入れる。
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./pyproject.toml
      ./src
      ./tests
    ];
  };

  build-system = with python3Packages; [ hatchling ];

  dependencies = with python3Packages; [
    gguf
    numpy
  ];

  nativeCheckInputs = with python3Packages; [ pytestCheckHook ];

  pythonImportsCheck = [ "merge_gguf_nextn" ];

  meta = {
    description = "GGUFの本体へ、別ファイルで配られたMTPのNextN層を足すコマンド";
    mainProgram = "merge-gguf-nextn";
    license = lib.licenses.asl20;
  };
}
