{ ... }:
{
  # VirtualBoxのゲストOSを想定。
  imports = [
    ../native-linux

    ./vanitas
  ];
  virtualisation.virtualbox.guest.enable = true;
}
