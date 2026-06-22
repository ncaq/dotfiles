_: {
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-WD_BLACK_SN850X_HS_2000GB_25393V801805";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
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
            nixos-boot = {
              size = "1G";
              type = "EA00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
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
                settings.allowDiscards = true;
                passwordFile = "/tmp/secret.password";
                content = {
                  type = "btrfs";
                  mountpoint = "/mnt/noa";
                  mountOptions = [
                    "noatime"
                    "compress=zstd"
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
    initrd = {
      availableKernelModules = [ "bcache" ];
      luks.devices = {
        "noa0" = {
          device = "/dev/disk/by-partlabel/disk-noa0-luks";
          crypttabExtraOpts = [
            "tpm2-device=auto"
          ];
        };
        "noa1" = {
          device = "/dev/disk/by-partlabel/disk-noa1-luks";
          crypttabExtraOpts = [
            "tpm2-device=auto"
          ];
        };
        "noa2" = {
          device = "/dev/disk/by-partlabel/disk-noa2-luks";
          crypttabExtraOpts = [
            "tpm2-device=auto"
          ];
        };
      };
    };
  };
  systemd.tmpfiles.rules = [
    # writebackモードを有効化
    "w /sys/block/bcache0/bcache/cache_mode - - - - writeback"
    "w /sys/block/bcache1/bcache/cache_mode - - - - writeback"
    "w /sys/block/bcache2/bcache/cache_mode - - - - writeback"
  ];
}
