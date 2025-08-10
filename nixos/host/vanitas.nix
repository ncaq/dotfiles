{ ... }:
{
  # VirtualBoxのゲストOSを想定。
  imports = [
    ../native-linux

    ./vanitas/boot.nix
    ./vanitas/disk.nix
  ];
  virtualisation.virtualbox.guest.enable = true;
}
