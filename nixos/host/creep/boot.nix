{
  boot = {
    loader = {
      limine = {
        secureBoot = {
          autoEnrollKeys = {
            # ThinkPad P16s Gen 2 AMDのファームウェアは、
            # `dbDefault`などのEFI変数を公開していないため、
            # デフォルトの`--firmware-builtin`は失敗します。
            # Microsoftの鍵だけをvendor鍵として登録します。
            extraArgs = [ "--microsoft" ];
          };
        };
      };
    };
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
