# ComfyUIのカスタムノードのComfyUI-Lora-Manager。
#
# Civitaiからの取得、プレビュー、トリガーワード、レシピを一元管理する。
#
# ソースをそのまま配置するだけなので、取得したソースそのものをパッケージにする。
# Pythonの依存はComfyUI本体のPython環境へ足す必要があるので、
# `passthru.pythonDependencies`として出して、使う側で`extraPythonPackages`へ渡す。
{
  lib,
  fetchFromGitHub,
}:
let
  src = fetchFromGitHub {
    owner = "willmiao";
    repo = "ComfyUI-Lora-Manager";
    tag = "v1.2.0";
    hash = "sha256-xwAXjD5/Yxlmz5F1bKlw6iksiRf+SuNAoeeUnhohfM4=";
  };
  # Pythonの依存をrequirements.txtから自動導出する。
  # 手書きのリストだとtag更新時に依存の増減へ追随し忘れて、
  # 実行時のImportErrorになるまで気付けない。
  # PyPI名をnixpkgsの属性名へ正規化して参照するので、
  # nixpkgsに存在しない依存が増えた場合は評価エラーで検出される。
  # バージョン制約は無視してnixpkgsのバージョンをそのまま使う。
  pythonDependencies =
    pythonPkgs:
    lib.pipe (builtins.readFile "${src}/requirements.txt") [
      (lib.splitString "\n")
      # 行頭のパッケージ名だけを取り出す。
      # コメント行と空行はマッチしないのでnullになる。
      (map (line: builtins.match "[[:space:]]*([A-Za-z0-9._-]+).*" line))
      (lib.filter (matched: matched != null))
      (map (matched: lib.toLower (builtins.replaceStrings [ "_" "." ] [ "-" "-" ] (lib.head matched))))
      # requirements.txt内の並び替えだけで環境が再ビルドされないように順序を正規化する。
      (lib.sort lib.lessThan)
      (map (name: pythonPkgs.${name}))
    ];
in
src.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    inherit pythonDependencies;
  };
})
