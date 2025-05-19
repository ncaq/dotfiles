{ ... }:
{
  boot = {
    loader = {
      grub = {
        enable = true;
        device = "/dev/dummy";
        useOSProber = true;
      };
    };
  };

  fileSystems = {
    "/" = {
      device = "/dev/dummy";
      fsType = "btrfs";
    };
  };
}
