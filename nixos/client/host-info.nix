# `client`層を読み込んだことを示す。
# `flake.nix`の`hostInfo`の`client`と食い違っていないかを`nixos/core/host-info.nix`が確かめる。
{
  local.client = true;
}
