{ ... }:
{
  # VirtualBoxのゲストOSを想定したNixOSのホスト定義。

  # 普通の環境はEFIが有効だと思うので予行演習としてVirtualBoxのEFIサポートを有効にしている。
  boot = {
    loader = {
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot/efi";
      };
      systemd-boot.enable = true; # NixOSのマジョリティに近いと思うから寄せているだけでこだわりはない。
    };
  };
  # VirtualBoxの標準的なデバイス名に合わせている。
  # 普通はデバイス名はUUIDとかで設定するけど、
  # そのへんの再現性が不明だし、
  # 仮想環境だから雑に済ませている。
  fileSystems = {
    "/boot" = {
      device = "/dev/sda1";
      fsType = "vfat";
      options = [
        "fmask=0077"
        "dmask=0077"
      ];
    };
    "/" = {
      device = "/dev/sda2";
      fsType = "ext4";
    };
  };
  virtualisation.virtualbox.guest.enable = true;
}
