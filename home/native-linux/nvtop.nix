{
  pkgs,
  osConfig ? null,
  ...
}:
let
  hasNvidia = osConfig != null && (osConfig.hardware.nvidia.enabled or false);
  hasAmd = osConfig != null && (osConfig.hardware.amdgpu.initrd.enable or false);
  nvtop =
    if hasNvidia && hasAmd then
      pkgs.nvtopPackages.full
    else if hasNvidia then
      pkgs.nvtopPackages.nvidia
    else if hasAmd then
      pkgs.nvtopPackages.amd
    else
      # fallback
      pkgs.nvtopPackages.full;
in
{
  home.packages = [ nvtop ];
}
