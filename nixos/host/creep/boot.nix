{
  boot = {
    loader = {
      limine = {
        # creepのESPはWindowsと同居するディスク上で1GBしか確保していません。
        # 共通設定の40世代だと、
        # xanmodカーネルの更新頻度の高さから異なるカーネルが13種類ほど混在し、
        # 1種類あたり約76MB(bzImage + initrd)で容量を使い切ってしまいました。
        # 世代数を減らして異なるカーネルの種類数を抑えます。
        maxGenerations = 20;
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
