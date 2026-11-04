{
  pkgs,
  osConfig ? null,
  ...
}:
let
  hasNvidia = osConfig != null && (osConfig.hardware.nvidia.enabled or false);
  obsPackage = pkgs.obs-studio.override {
    cudaSupport = hasNvidia;
    # ブラウザソースは使っていない。
    # OBSはnixpkgsのcef-binaryではなく自前で固定した古いCEFを使うため、
    # 有効にすると更新されないChromiumを抱え込むことになる。
    browserSupport = false;
  };
in
{
  programs.obs-studio = {
    enable = true;
    package = obsPackage;
    # プラグインはnixpkgs既定のobs-studioに対してビルドされていて、
    # そのままだと上で外したCEF込みの既定ビルドが閉包に残る。
    # こちらのobs-studioに差し替えてビルドし、
    # 実際に起動するOBSと同じビルドにプラグインを揃える。
    plugins = map (plugin: plugin.override { obs-studio = obsPackage; }) (
      with pkgs.obs-studio-plugins;
      [
        obs-backgroundremoval
        obs-gstreamer
        obs-pipewire-audio-capture
        obs-vaapi
        obs-vkcapture
        wlrobs
      ]
    );
  };
}
