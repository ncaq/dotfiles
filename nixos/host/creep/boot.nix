{
  boot = {
    initrd = {
      luks.devices = {
        nixos-root = {
          device = "/dev/disk/by-label/nixos-root-crypt";
          allowDiscards = true;
          crypttabExtraOpts = [
            "fido2-device=auto"
          ];
        };
      };
    };
  };
}
