{ ... }:
{
  # VirtualBoxのゲストOSを想定。
  imports = [ ./vanitas/disk.nix ];
  # 普通の環境はEFIが有効だと思うので予行演習としてVirtualBoxのEFIサポートを有効にしている。
  boot = {
    loader = {
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot/efi";
      };
      timeout = 1;
      systemd-boot = {
        enable = true;
        consoleMode = "max";
      };
    };
  };
  virtualisation.virtualbox.guest.enable = true;
}
