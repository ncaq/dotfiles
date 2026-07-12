{ lib, ... }: {
  boot = {
    loader = {
      limine.enable = lib.mkForce false; # seminarのlimine対応は後でやります。
      systemd-boot = {
        enable = true;
        consoleMode = "auto";
        xbootldrMountPoint = "/boot";
        configurationLimit = 40;
      };
    };
    initrd = {
      luks.devices = {
        nixos-root = {
          device = "/dev/disk/by-partlabel/disk-main-nixos-root";
          allowDiscards = true;
          crypttabExtraOpts = [
            "tpm2-device=auto"
          ];
        };
      };
    };
  };
}
