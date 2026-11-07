# Comfy-Orgの公式CLI。
#
# nixpkgsにはまだ無いので自前でパッケージ化している。
# 現状使う見込みのある機能は`comfy run`と`comfy workflow`ぐらい。
{
  lib,
  python3Packages,
  fetchFromGitHub,
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

  # テストはComfyUIのインストール先やネットワークに触るものが多いので走らせない。
  doCheck = false;

  meta = {
    description = "Comfy-Orgの公式CLI";
    homepage = "https://github.com/Comfy-Org/comfy-cli";
    mainProgram = "comfy";
    license = lib.licenses.gpl3Only;
  };
}
