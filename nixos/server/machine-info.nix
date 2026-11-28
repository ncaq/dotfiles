{
  # hostnamectlでのChassisタイプをserverに設定
  environment.etc."machine-info".text = ''
    CHASSIS=server
  '';
  # `server`層を読み込んだことを示す。
  # `flake.nix`の`hostInfo`の`server`と食い違っていないかを`nixos/core/host-info.nix`が確かめる。
  local.server = true;
}
