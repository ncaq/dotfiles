{ ... }:
{
  # VirtualBoxのゲストOSを想定。
  imports = [
    ../native-linux

    ./vanitas/disk.nix
  ];
  # 普通の環境はEFIが有効だと思うので予行演習としてVirtualBoxのEFIサポートを有効にしている。
  boot = {
    loader = {
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/efi";
      };
      timeout = 1;
      systemd-boot = {
        enable = true;
        consoleMode = "auto";
        xbootldrMountPoint = "/boot";
      };
    };
  };
  virtualisation.virtualbox.guest.enable = true;
}
