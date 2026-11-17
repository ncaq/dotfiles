# ComfyUIのカスタムノードのComfyUI-SeedVR2_VideoUpscaler。
#
# 複数フレームを同時に参照して時間的一貫性を保つ動画超解像。
#
# Pythonの依存はComfyUI本体のPython環境へ足す必要があるので、
# `passthru.pythonDependencies`として出して、使う側で`extraPythonPackages`へ渡す。
{
  applyPatches,
  fetchFromGitHub,
}:
(applyPatches {
  src = fetchFromGitHub {
    owner = "numz";
    repo = "ComfyUI-SeedVR2_VideoUpscaler";
    rev = "4490bd1f482e026674543386bb2a4d176da245b9";
    hash = "sha256-6nsqFflLw9vYH/du35ET46fdAm1NMjjTe2bA8JmaBE4=";
  };
  patches = [ ./lossless.patch ];
  # GNU patchの既定はfuzz 2とオフセット探索で文脈のずれを黙って許容する。
  # 上流のrev更新でパッチの文脈が一致しなくなった時に、
  # 意味の違う位置へ適用されるより確実にビルド失敗させたい。
  patchFlags = [
    "-p1"
    "-F0"
  ];
}).overrideAttrs
  (old: {
    passthru = (old.passthru or { }) // {
      # requirements.txtのうち、comfyui-nixのPython環境に同梱されていないもの。
      # DiTモデルの位置埋め込み(`src/models/dit_*/rope.py`)がimportする。
      # torchなどの他の依存は同梱のものを使う。
      pythonDependencies = pythonPkgs: [ pythonPkgs.rotary-embedding-torch ];
    };
  })
