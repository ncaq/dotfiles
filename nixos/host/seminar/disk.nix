{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-WD_BLACK_SN850X_HS_2000GB_25393V801805";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "2G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/efi";
                mountOptions = [
                  "noatime"
                  "fmask=0077"
                  "dmask=0077"
                ];
              };
            };
            nixos-root = {
              size = "100%";
              type = "8300";
              content = {
                type = "luks";
                name = "nixos-root";
                settings.allowDiscards = true;
                # フォーマット時のみ使う一時パスワードファイル。
                passwordFile = "/tmp/secret.password";
                content = {
                  type = "btrfs";
                  subvolumes = {
                    "@" = {
                      mountpoint = "/";
                      mountOptions = [
                        "noatime"
                        "compress=zstd"
                      ];
                    };
                    "@nix-store" = {
                      mountpoint = "/nix/store";
                      mountOptions = [
                        "noatime"
                        "compress=zstd"
                      ];
                    };
                    "@swap" = {
                      mountpoint = "/swap";
                      mountOptions = [
                        "noatime"
                      ];
                    };
                    "@var-log" = {
                      mountpoint = "/var/log";
                      mountOptions = [
                        "noatime"
                        "compress=zstd"
                      ];
                    };
                    "@snapshots" = {
                      mountpoint = "/.snapshots";
                      mountOptions = [
                        "noatime"
                        "compress=zstd"
                      ];
                    };
                  };
                };
              };
            };
          };
        };
      };
      # # diskoはbcacheを直接サポートしていないため、
      # # 一部は以下のように手動で設定する必要があります。
      # # bcacheデバイスの作成
      # # キャッシュデバイス(SSD)
      # CACHE_DEVICE=/dev/disk/by-id/nvme-WD_BLACK_SN770_1TB_242810800421
      # sudo make-bcache --cache --writeback --discard $CACHE_DEVICE
      # # バッキングデバイス(HDD)
      # sudo make-bcache --bdev --writeback --discard /dev/disk/by-id/ata-WDC_WD121PURZ-85GUCY0_2AGN938Y
      # sudo make-bcache --bdev --writeback --discard /dev/disk/by-id/ata-WDC_WD80EAAZ-00BXBB0_WD-RD2PKLEH
      # sudo make-bcache --bdev --writeback --discard /dev/disk/by-id/ata-WDC_WD80EAZZ-00BKLB0_WD-CA2HPAUK
      # # キャッシュセットに接続
      # CACHE_SET_UUID=$(sudo bcache-super-show $CACHE_DEVICE|grep 'cset.uuid'|awk '{print $2}')
      # for i in 0 1 2; do sudo zsh -c "echo $CACHE_SET_UUID > /sys/block/bcache$i/bcache/attach"; done
      # # パスワードファイル作成
      # sudo nano /tmp/secret.password
      # # 初期インストール時以外はフォーマットを手動で済ませる。
      # # diskoのformatを使うとUUIDが変わってUEFIのブートエントリが壊れる。
      # # 初期インストール時は以下のdiskoのformatとmountを使っても良い。
      # install.sh
      # # TPM2登録
      # sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-partlabel/disk-noa0-luks
      # sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-partlabel/disk-noa1-luks
      # sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-partlabel/disk-noa2-luks
      noa0 = {
        type = "disk";
        device = "/dev/bcache0";
        content = {
          type = "gpt";
          partitions = {
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "noa0";
                initrdUnlock = false;
                settings.allowDiscards = true;
                passwordFile = "/tmp/secret.password";
                content = {
                  type = "btrfs";
                  mountpoint = "/mnt/noa";
                  mountOptions = [
                    "noatime"
                    "compress=zstd"
                    # ディスクが欠けてマウントできなくても、
                    # emergency modeに落ちずに起動を続ける。
                    # noaは起動に必須ではないので、
                    # sshで入って調べられる方を優先する。
                    # マウントされていない時にルートのSSDへ書き込まれないための対策は、
                    # `noa.nix`と使う側のユニットの`RequiresMountsFor`にある。
                    "nofail"
                    # TODO: noa2(WD121PURZ)が2026-11-14にSATAリンクから脱落したための一時的な措置。
                    # https://github.com/ncaq/dotfiles/issues/1732
                    # ディスクが欠けたままマウントできるようにする。
                    # 自動でマウントするには`noa-degraded-automount.nix`のudevルールも要る。
                    # 障害対応が終わったら、そのファイルと一緒に外す。
                    # 常に付けているとディスクの脱落に気付きにくくなり、
                    # 欠けている間の書き込みは冗長性が落ちる。
                    "degraded"
                  ];
                  subvolumes = {
                    # snapperスナップショットの転送先。
                    # 独立したサブボリュームにすることで、
                    # noa config(SUBVOLUME = /mnt/noa)のタイムラインスナップショットに含まれず、
                    # バックアップの二重保存を避けられる。
                    # `mountpoint`は指定しない。
                    # トップレベルがマウントされている`/mnt/noa/snapshot-backup`として参照でき、
                    # 別途マウントユニットを生成するとブート時のマウント失敗でemergencyに落ちるため。
                    "snapshot-backup" = { };
                  };
                  extraArgs = [
                    "-d raid1"
                    "/dev/mapper/noa0"
                    "/dev/mapper/noa1"
                    "/dev/mapper/noa2"
                    "-m raid1c3"
                    "/dev/mapper/noa0"
                    "/dev/mapper/noa1"
                    "/dev/mapper/noa2"
                    "-s raid1c3"
                    "/dev/mapper/noa0"
                    "/dev/mapper/noa1"
                    "/dev/mapper/noa2"
                  ];
                };
              };
            };
          };
        };
      };
      noa1 = {
        type = "disk";
        device = "/dev/bcache1";
        content = {
          type = "gpt";
          partitions = {
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "noa1";
                initrdUnlock = false;
                settings.allowDiscards = true;
                passwordFile = "/tmp/secret.password";
              };
            };
          };
        };
      };
      noa2 = {
        type = "disk";
        device = "/dev/bcache2";
        content = {
          type = "gpt";
          partitions = {
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "noa2";
                initrdUnlock = false;
                settings.allowDiscards = true;
                passwordFile = "/tmp/secret.password";
              };
            };
          };
        };
      };
    };
  };
  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 64 * 1024; # 物理メモリのサイズと合わせています。
    }
  ];
  boot = {
    kernelModules = [ "bcache" ];
    initrd.availableKernelModules = [ "bcache" ];
  };
  # noaのLUKSはinitrdではなく、
  # ルートへ切り替わった後に解錠する。
  # TPM2による復号の脅威モデルは`boot.nix`の`nixos-root`と同じ。
  #
  # `nofail`は`/mnt/noa`のマウントオプションの`nofail`と同じ理由で、
  # ディスクが欠けて解錠できなくても起動を続けるために付ける。
  # `nofail`を付けた解錠は`cryptsetup.target`より前に順序付けられないので、
  # initrdに置くと解錠が終わる前にルートへ切り替わる。
  # 途中だった解錠は止められたままやり直されず、
  # ディスクが揃っていてもマウントされなくなる。
  # noaは起動に必須ではないので、
  # 解錠を待つものが`/mnt/noa`のマウントだけになる切り替えの後に置く。
  environment.etc.crypttab.text = ''
    noa0 /dev/disk/by-partlabel/disk-noa0-luks - tpm2-device=auto,discard,nofail
    noa1 /dev/disk/by-partlabel/disk-noa1-luks - tpm2-device=auto,discard,nofail
    noa2 /dev/disk/by-partlabel/disk-noa2-luks - tpm2-device=auto,discard,nofail
  '';
  systemd.tmpfiles.rules = [
    # writebackモードを有効化
    # `-`を付けて、
    # ディスクが欠けてbcacheのデバイスが無くてもsystemd-tmpfilesを失敗させない。
    "w- /sys/block/bcache0/bcache/cache_mode - - - - writeback"
    "w- /sys/block/bcache1/bcache/cache_mode - - - - writeback"
    "w- /sys/block/bcache2/bcache/cache_mode - - - - writeback"
  ];
}
