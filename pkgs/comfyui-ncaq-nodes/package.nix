# ComfyUIの自作カスタムノードをまとめたもの。
#
# 出力はそのまま`custom_nodes/`配下の1ディレクトリになる形をしていて、
# `nixos/host/bullet/comfyui/custom-node.nix`が`services.comfyui.customNodes`へ渡す。
# どのノードがあるかは`src/__init__.py`に並んでいる。
#
# Pythonで書いているのは、ComfyUIがノードをPythonのモジュールとして読み込むからである。
# 補助プログラムの言語の基準では、ライブラリが言語を決める場合に当たる。
#
# ビルドにComfyUIのPython環境は使わず、インタプリタだけを借りる。
# CUDA版torchを含む環境は巨大だからである。
# バイトコンパイルとテストだけならインタプリタと少しのライブラリで足りる。
# ComfyUI本体やtorchに触れる部分の誤りは、
# ComfyUIの環境を見る`checks.pyright`が型検査で拾う。
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  # comfyui-nixのoverlayが生やすCPU版のComfyUI。
  # 全てのシステムにある。
  # 今はCUDA版と同じ版のPythonを使っているが、揃っていることは検査していない。
  comfy-ui,
}:
let
  # comfyui-nixが使うPythonでバイトコンパイルしてテストする。
  # 版を手で書くと、comfyui-nixがPythonを上げた時に追従し忘れて、
  # ComfyUIのPythonに無い構文に依存してもテストで気付けなくなる。
  #
  # 実際にノードを読み込むCUDA版と版がずれても、動作は変わらない。
  # 配ったバイトコードが使われず、起動のたびにコンパイルし直されるだけである。
  python = comfy-ui.pythonRuntime.python.withPackages (
    pythonPkgs: with pythonPkgs; [
      pytest
      requests
    ]
  );
  # RewriteEditPromptが使うPE-I2Iは公式のシステムプロンプトと組で学習されているので、
  # そのファイルを公式リポジトリから取ってノードの隣へ置く。
  # Qwen Research Licenseのファイルなので、
  # 本文をこのリポジトリへ取り込んで再配布することはしない。
  qwenImage21 = fetchFromGitHub {
    owner = "QwenLM";
    repo = "Qwen-Image-2.1";
    rev = "fb7ae1d1f9611cd91524d03c53c5246b36ac8577";
    hash = "sha256-iXaBv6x0cDooNBRBemGQbrChZ96xLgYjgxThTYBmtKU=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "comfyui-ncaq-nodes";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./pyproject.toml
      ./src
      ./tests
    ];
  };

  nativeBuildInputs = [ python ];

  # nixpkgsのPythonパッケージと同じく、バイトコードをビルド時に作って一緒に配る。
  # storeは読み取り専用なので、配らなければComfyUIは起動のたびにコンパイルし直す。
  #
  # 文法エラーがあるとここで落ちる。
  # 以前は構文検査だけのために自前で`compile()`を呼んでいたが、
  # ビルドの成果物として作れば検査は副産物になる。
  #
  # stdenvが`SOURCE_DATE_EPOCH`を設定しているので、
  # バイトコードはソースの更新日時ではなくハッシュで照合する形式になり、
  # storeへ入って更新日時が変わっても無効にならない。
  buildPhase = ''
    runHook preBuild
    python -m compileall -q src
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    # `src`はそのまま`$out`へ複製するので、テストがキャッシュを書き足さないようにする。
    PYTHONDONTWRITEBYTECODE=1 pytest -p no:cacheprovider
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    cp -r src $out
    cp ${qwenImage21}/prompt_rewrite/prompts/system_prompt_edit.txt $out/system_prompt_edit.txt

    runHook postInstall
  '';

  meta.description = "ComfyUIの自作カスタムノードをまとめたもの";
}
