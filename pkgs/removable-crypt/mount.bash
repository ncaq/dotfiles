#!/usr/bin/env bash
set -euo pipefail

# 暗号化されたリムーバブルデバイスを復号して`/mnt/<名前>`へマウントするスクリプト。
#
# btrfsならマウント後にsnapperでスナップショットを取り、古いものを掃除します。
# 途中で失敗した時は、そこまでに行ったマウントと復号を巻き戻します。
#
# 環境変数は全て`default.nix`のラッパーが設定します。
#   REMOVABLE_CRYPT_NAME                マッパーの名前。マウントポイントとsnapperの設定の名前も兼ねます。
#   REMOVABLE_CRYPT_DEVICE_ID           `/dev/disk/by-id/`以下のデバイスのID。
#   REMOVABLE_CRYPT_MOUNT_OPTIONS       btrfs以外で使う、カンマ区切りのマウントオプション。
#   REMOVABLE_CRYPT_BTRFS_MOUNT_OPTIONS btrfsで使う、カンマ区切りのマウントオプション。

# bashはエラーの頭に変数名を付けるので、メッセージには変数名を書かない。
# マウントオプションは空でも良いので、未設定の時だけ止める。
mapper_name=${REMOVABLE_CRYPT_NAME:?is not set}
device_id=${REMOVABLE_CRYPT_DEVICE_ID:?is not set}
mount_options=${REMOVABLE_CRYPT_MOUNT_OPTIONS?is not set}
btrfs_mount_options=${REMOVABLE_CRYPT_BTRFS_MOUNT_OPTIONS?is not set}

if [[ ! -w /dev/mapper/control ]]; then
  echo "error: no permission to access /dev/mapper/control (use sudo)" >&2
  exit 1
fi

device_path="/dev/disk/by-id/$device_id"
target_user="${SUDO_USER:-$USER}"
mount_point="/mnt/$mapper_name"

mapper_attached=0
mounted=0

cleanup() {
  if [[ $mounted -eq 1 ]]; then
    umount "$mount_point" 2>/dev/null || true
  fi
  if [[ -d $mount_point ]]; then
    rmdir "$mount_point" 2>/dev/null || true
  fi
  if [[ $mapper_attached -eq 1 ]]; then
    systemd-cryptsetup detach "$mapper_name" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ ! -e $device_path ]]; then
  echo "error: device not found: $device_path" >&2
  exit 1
fi

systemd-cryptsetup attach "$mapper_name" "$device_path"
mapper_attached=1

mkdir -p "$mount_point"
chown "$target_user:" "$mount_point"

fs_type=$(blkid -s TYPE -o value "/dev/mapper/$mapper_name")
if [[ $fs_type == "btrfs" ]]; then
  mount -o "$btrfs_mount_options" "/dev/mapper/$mapper_name" "$mount_point"
else
  mount -o "$mount_options" "/dev/mapper/$mapper_name" "$mount_point"
fi
mounted=1

chown "$target_user:" "$mount_point"

# btrfs: create snapshot and cleanup old ones
if [[ $fs_type == "btrfs" ]]; then
  if [[ ! -d "$mount_point/.snapshots" ]]; then
    btrfs subvolume create "$mount_point/.snapshots"
  fi
  snapper -c "$mapper_name" create --cleanup-algorithm timeline --description "mount"
  snapper -c "$mapper_name" cleanup timeline
fi

# Success - disable cleanup
trap - EXIT
