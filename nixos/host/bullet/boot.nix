_: {
  boot = {
    loader = {
      limine = {
        # 他のSSDに入っているWindowsのブートマネージャにチェインロードします。
        # vfatのボリュームシリアルはGUID形式ではないため、
        # GPTパーティションGUID(PARTUUID)で指定します。
        extraEntries = ''
          /Windows Game
              protocol: efi_chainload
              path: guid(4df43761-322e-44ef-9219-3b923e95d5b6):/EFI/Microsoft/Boot/bootmgfw.efi

          /Windows Work
              protocol: efi_chainload
              path: guid(386d2f0a-f36e-4678-93d1-84c7df8665a0):/EFI/Microsoft/Boot/bootmgfw.efi
        '';
      };
    };
  };
}
