{
  pkgs,
  osConfig ? null,
  ...
}:
let
  hasNvidia = osConfig != null && (osConfig.hardware.nvidia.enabled or false);
in
{
  programs.obs-studio = {
    enable = true;
    package = pkgs.obs-studio.override {
      cudaSupport = hasNvidia;
    };
    plugins = with pkgs.obs-studio-plugins; [
      obs-backgroundremoval
      obs-gstreamer
      obs-pipewire-audio-capture
      obs-vaapi
      obs-vkcapture
      wlrobs
    ];
  };
}
