{
  boot = {
    loader = {
      limine = {
        secureBoot = {
          autoEnrollKeys = {
            # seminarはデュアルブートしていないので、
            # Microsoftの鍵を登録する必要はありません。
            extraArgs = [ "--firmware-builtin" ];
          };
        };
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
