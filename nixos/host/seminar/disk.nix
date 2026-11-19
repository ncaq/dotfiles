{ config, lib, ... }:
let
  # `/mnt/noa`のbtrfsを構成するメンバの番号。
  # ディスクを足す時はここを増やす。
  # diskoの定義とmkfsの引数とbcacheのキャッシュモードの設定が、
  # この一覧から作られる。
  noaMemberIndices = lib.range 0 3;
  noaMappers = map (index: "/dev/mapper/noa${toString index}") noaMemberIndices;
  # メンバ1台分のdiskoの定義。
  # bcacheのデバイスの上にGPTを切って、
  # 全体をLUKSにする。
  # `extraLuksContent`はLUKSの定義に足す属性で、
  # ファイルシステムを持つメンバだけが渡す。
  mkNoaMember = index: extraLuksContent: {
    type = "disk";
    device = "/dev/bcache${toString index}";
    content = {
      type = "gpt";
      partitions.luks = {
        size = "100%";
        content = {
          type = "luks";
          name = "noa${toString index}";
          initrdUnlock = false;
          settings.allowDiscards = true;
          passwordFile = "/tmp/secret.password";
        }
        // extraLuksContent;
      };
    };
  };
  # initrdで解錠しないLUKSのパーティション。
  # `initrdUnlock = false`にしたものは誰も解錠しなくなるので、
  # 下の`environment.etc.crypttab`へ渡して切り替えの後に解錠する。
  # マッパ名とデバイスをdiskoの定義から取ることで、
  # ディスクの追加や改名で片方だけ変えて食い違うことを防ぐ。
  lateUnlockLuksPartitions =
    lib.filter
      (
        partition:
        partition.content != null && partition.content.type == "luks" && !partition.content.initrdUnlock
      )
      (
        lib.concatMap (disk: lib.attrValues (disk.content.partitions or { })) (
          lib.attrValues config.disko.devices.disk
        )
      );
in
{
  assertions = [
    {
      # 理由は下の`environment.etc.crypttab`のコメントに書いている。
      # `boot.nix`の`nixos-root`にならってinitrdへ戻すと、
      # ディスクが揃っていても`/mnt/noa`がマウントされなくなる。
      assertion = !lib.any (lib.hasPrefix "noa") (lib.attrNames config.boot.initrd.luks.devices);
      message = "noaのLUKSはinitrdで解錠しないでください。diskoの定義で`initrdUnlock = false`にします。";
    }
  ];
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
      # sudo make-bcache --bdev --writeback --discard /dev/disk/by-id/ata-WDC_WD80EFPX-68C4ZN0_WD-1F1K9E0U
      # # キャッシュセットに接続
      # CACHE_SET_UUID=$(sudo bcache-super-show $CACHE_DEVICE|grep 'cset.uuid'|awk '{print $2}')
      # for i in 0 1 2 3; do sudo zsh -c "echo $CACHE_SET_UUID > /sys/block/bcache$i/bcache/attach"; done
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
      # sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-partlabel/disk-noa3-luks
      #
      # # 稼働中のファイルシステムへ後からディスクを足す時は、
      # # diskoのformatを使わずに手動で作る。
      # # 上と同じ`make-bcache`とキャッシュセットへの接続の後に、
      # # パーティションを作ってLUKSで初期化する。
      # sudo sgdisk --new=1:0:0 --typecode=1:8300 --change-name=1:disk-noa3-luks /dev/bcache3
      # sudo cryptsetup luksFormat --type luks2 /dev/disk/by-partlabel/disk-noa3-luks
      # sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-partlabel/disk-noa3-luks
      # # `settings.allowDiscards`に当たるフラグをLUKSのヘッダへ残す。
      # sudo systemd-cryptsetup attach noa3 /dev/disk/by-partlabel/disk-noa3-luks - tpm2-device=auto
      # sudo cryptsetup refresh --allow-discards --persistent noa3
      # sudo btrfs device add /dev/mapper/noa3 /mnt/noa
      # # 足しただけでは既存のデータは動かず、
      # # 新しいディスクはこれから書く分に使われる。
      # # 全体を配り直すbalanceは時間がかかるので、
      # # 必要な時にだけ別途実行する。
      #
      # ファイルシステムの定義は先頭のメンバのLUKSの中に置く。
      noa0 = mkNoaMember 0 {
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
            # `degraded`は付けない。
            # 付けていると、
            # 解錠が済んだメンバだけで黙ってマウントされて、
            # 残りのメンバが古くなる。
            # ディスクが欠けた時は、
            # 状況を確かめてから手で`-o degraded`を付けてマウントする。
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
          ]
          ++ noaMappers
          ++ [ "-m raid1c3" ]
          ++ noaMappers
          ++ [ "-s raid1c3" ]
          ++ noaMappers;
        };
      };
    }
    # 残りのメンバはLUKSだけを持つ。
    // lib.listToAttrs (
      map (index: lib.nameValuePair "noa${toString index}" (mkNoaMember index { })) (
        lib.tail noaMemberIndices
      )
    );
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
  # 解錠が途中で止められない切り替えの後に置く。
  #
  # 切り替えの後では全てのメンバがほぼ同時に解錠される。
  # systemdの`64-btrfs.rules`は、
  # 複数デバイスのbtrfsの全メンバがカーネルへ登録されるまで、
  # メンバのデバイスをreadyにしない。
  # `/mnt/noa`のマウントは`/dev/mapper/noa0`がreadyになるのを待つので、
  # noa0の解錠が先に済んでも、
  # 全メンバが揃うまでマウントは始まらない。
  # この待ちを飛ばすudevルールや`degraded`を足すと、
  # 解錠が済んだメンバだけでマウントされる。
  #
  # `discard`はdiskoの`settings.allowDiscards`に当たる。
  environment.etc.crypttab.text = lib.concatMapStrings (
    partition:
    let
      options = [
        "tpm2-device=auto"
      ]
      ++ lib.optional (partition.content.settings.allowDiscards or false) "discard"
      ++ [ "nofail" ];
    in
    "${partition.content.name} ${partition.device} - ${lib.concatStringsSep "," options}\n"
  ) lateUnlockLuksPartitions;
  # writebackモードを有効化
  # `-`を付けて、
  # ディスクが欠けてbcacheのデバイスが無くてもsystemd-tmpfilesを失敗させない。
  systemd.tmpfiles.rules = map (
    index: "w- /sys/block/bcache${toString index}/bcache/cache_mode - - - - writeback"
  ) noaMemberIndices;
}
