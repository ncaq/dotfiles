# PFNの翻訳特化モデルPLaMo Translateをローカルで動かすCLI。
#
# nixpkgsにはまだ無いので自前でパッケージ化している。
# Linuxでは推論をllama.cppの`llama-server`へ任せ、
# モデルのGGUFは初回の実行時にHugging Faceのキャッシュへ取得する。
{
  lib,
  python3Packages,
  fetchFromGitHub,
  llama-cpp,
  versionCheckHook,
  # 既定で使うモデル。
  # `null`なら上流の既定のモデルを使う。
  # `--model`で指定すればこの既定値は上書きされる。
  model ? null,
  # 投機的デコーディングに使うドラフトのモデル。
  # 上流は既定のモデル以外ではドラフトを自動で付けないので、
  # 既定以外の`model`で速度が欲しい場合に指定する。
  # `--draft-model`で指定すればこの既定値は上書きされる。
  draftModel ? null,
}:
python3Packages.buildPythonApplication rec {
  pname = "plamo-translate-cli";
  version = "1.2.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "pfnet";
    repo = "plamo-translate-cli";
    tag = version;
    hash = "sha256-d8DXxRqb6YiHC4+BGKOmNZ7DgceTan6tpaEWJlhN9a8=";
  };

  build-system = with python3Packages; [ hatchling ];

  # macOSのMLXの依存は環境マーカーで外れるので、Linuxで要るのはこれだけ。
  dependencies =
    with python3Packages;
    [
      httpx
      huggingface-hub
      mcp
      transformers
    ]
    ++ mcp.optional-dependencies.cli;

  # PATHに頼らず使う`llama-server`を固定する。
  # PLaMo 3に対応した`llama-server`はb11960以降が必要なので、
  # 呼び出し側から十分新しいllama.cppを渡す。
  makeWrapperArgs = [
    "--set-default"
    "PLAMO_TRANSLATE_CLI_LLAMA_SERVER"
    (lib.getExe' llama-cpp "llama-server")
  ]
  ++ lib.optionals (model != null) [
    "--set-default"
    "PLAMO_TRANSLATE_CLI_MODEL_NAME"
    model
  ]
  # ドラフトには環境変数が無いので引数で渡す。
  # `--add-flags`は利用者の引数より前に入り、
  # argparseは後に書いた方を採るので利用者の指定が勝つ。
  # Pythonのラッパーは`makeWrapperArgs`を空白で分割するので、
  # オプション名と値を別々の`--add-flags`で渡す。
  ++ lib.optionals (draftModel != null) [
    "--add-flags"
    "--draft-model"
    "--add-flags"
    draftModel
  ];

  # 上流のテストはモデルの取得や推論を伴うものが多いので走らせない。
  # Pythonの派生は`doCheck`を`doInstallCheck`へ写すので、
  # `versionCheckHook`を動かすには`doCheck`の方を立てる必要がある。
  doCheck = true;
  pythonImportsCheck = [ "plamo_translate" ];
  nativeInstallCheckInputs = [ versionCheckHook ];

  meta = {
    description = "PLaMo Translateでローカル翻訳するCLI";
    homepage = "https://github.com/pfnet/plamo-translate-cli";
    license = lib.licenses.asl20;
    mainProgram = "plamo-translate";
  };
}
