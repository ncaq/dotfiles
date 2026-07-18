{
  pkgs,
  osConfig ? null,
  ...
}:
let
  hasNvidia = osConfig != null && (osConfig.hardware.nvidia.enabled or false);
  hasAmd = osConfig != null && (osConfig.hardware.amdgpu.initrd.enable or false);
  btop-usable =
    with pkgs;
    if hasNvidia then
      btop-cuda
    else if hasAmd then
      btop-rocm
    else
      btop;
in
{
  programs = {
    btop = {
      enable = true;
      package = btop-usable;
      settings = {
        # btrfsのサブボリュームはルートと同じデバイスなので、
        # I/Oも空き容量も同じ内容が重複表示されるだけになるため除外する。
        disks_filter = "exclude=/.snapshots /var/log /nix/store /swap";
      };
    };
  };
}
