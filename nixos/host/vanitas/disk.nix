{ ... }:
{
  # VirtualBoxの標準的なデバイス名に合わせている。
  # 普通はデバイス名はUUIDとかで設定するけど、
  # そのへんの再現性が不明だし、
  # 仮想環境だから雑に済ませている。
  fileSystems = {
    "/efi" = {
      device = "/dev/sda1";
      fsType = "vfat";
      options = [
        "noatime"
        "fmask=0077"
        "dmask=0077"
      ];
    };
    "/boot" = {
      device = "/dev/sda2";
      fsType = "vfat";
      options = [
        "noatime"
        "fmask=0077"
        "dmask=0077"
      ];
    };
    "/" = {
      device = "/dev/sda3";
      fsType = "ext4";
      options = [
        "noatime"
      ];
    };
  };
}
