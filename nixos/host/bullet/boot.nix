{
  boot = {
    loader = {
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/efi";
      };
      timeout = 1;
      limine = {
        enable = true;
        # ディスク容量を埋め尽くさないように上限を定めます。
        maxGenerations = 50;
        style = {
          interface = {
            # ブート時はGPUを効率的に使えないことが多いため解像度を下げて負荷を減らします。
            resolution = "1920x1080";
          };
        };
        # Nixが直接対応していない設定を直接書き込みます。
        extraConfig = ''
          # 最後に起動したエントリを記憶して次回起動時に自動選択します。
          remember_last_entry: yes
          # ブートローダーでも慣れたdvorak入力を使ってトラブルシューティングを楽にします。
          keyboard_layout: dvorak
        '';
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
    initrd = {
      systemd = {
        enable = true;
      };
    };
  };
}
