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
        # プリインストールされているWindowsのブートマネージャにチェインロードします。
        # Windowsのブートマネージャは最初からESPとして使われていたパーティションにあります。
        # vfatのボリュームシリアルはGUID形式ではないため、
        # GPTパーティションGUID(PARTUUID)で指定します。
        extraEntries = ''
          /Windows
              protocol: efi_chainload
              path: guid(9fc93af9-07db-45df-a334-97e57e820daf):/EFI/Microsoft/Boot/bootmgfw.efi
        '';
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
