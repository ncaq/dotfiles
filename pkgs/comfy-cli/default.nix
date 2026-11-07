# Comfy-Orgの公式CLI。
#
# nixpkgsにはまだ無いので自前でパッケージ化している。
# 現状使う見込みのある機能は`comfy run`と`comfy workflow`と`comfy jobs`ぐらい。
{
  lib,
  python3Packages,
  fetchFromGitHub,
  versionCheckHook,
}:
python3Packages.buildPythonApplication rec {
  pname = "comfy-cli";
  version = "1.25.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "Comfy-Org";
    repo = "comfy-cli";
    tag = "v${version}";
    hash = "sha256-0AtvBHfjpFh+x+SZMHZenK9BZ+Msh6QURN5eZIaZYGk=";
  };

  # 上流は`pyproject.toml`のバージョンを`0.0.0`のまま置いて、
  # 公開のワークフローがタグから書き込む。
  # そのままだと`comfy --version`が`0.0.0`になるので、タグの値を書き込む。
  postPatch = ''
    substituteInPlace pyproject.toml --replace-fail 'version = "0.0.0"' 'version = "${version}"'
  '';

  build-system = with python3Packages; [ setuptools ];

  # 上限や下限がnixpkgsの版と少しずれているだけなので緩める。
  pythonRelaxDeps = [
    "blake3"
    "mixpanel"
    "posthog"
  ];

  dependencies = with python3Packages; [
    blake3
    certifi
    charset-normalizer
    cookiecutter
    gitpython
    httpx
    imageio-ffmpeg
    mixpanel
    packaging
    pathspec
    posthog
    psutil
    pyyaml
    questionary
    requests
    rich
    ruff
    semver
    tomlkit
    typer
    typing-extensions
    uv
    websocket-client
  ];

  # 上流のテストはComfyUIのインストール先やネットワークに触るものが多いので走らせない。
  # `pytestCheckHook`を入れていないので、`doCheck`を立てても走るのは以下のフックだけになる。
  # Pythonの派生は`doCheck`を`doInstallCheck`へ写すので、
  # `versionCheckHook`を動かすには`doCheck`の方を立てる必要がある。
  #
  # ネットワークにもComfyUIにも触れない最低限の検査として、
  # 版の縛りを緩めた依存のAPIが変わってimportで壊れた時と、
  # `postPatch`で書き込んだ版が`comfy --version`に出ない時にビルドで気付けるようにする。
  doCheck = true;
  pythonImportsCheck = [ "comfy_cli" ];
  nativeInstallCheckInputs = [ versionCheckHook ];

  meta = {
    description = "Comfy-Orgの公式CLI";
    homepage = "https://github.com/Comfy-Org/comfy-cli";
    mainProgram = "comfy";
    license = lib.licenses.gpl3Only;
  };
}
