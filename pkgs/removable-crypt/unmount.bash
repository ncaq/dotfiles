#!/usr/bin/env bash
set -euo pipefail

# `mount.bash`でマウントしたリムーバブルデバイスをアンマウントして復号を解くスクリプト。
#
# btrfsならアンマウントの前にsnapperでスナップショットを取ります。
# 途中の手順が失敗しても残りの手順は続け、どれかが失敗していれば最後に非0で終わります。
#
# 環境変数は`default.nix`のラッパーが設定します。
#   REMOVABLE_CRYPT_NAME マッパーの名前。マウントポイントとsnapperの設定の名前も兼ねます。

# bashはエラーの頭に変数名を付けるので、メッセージには変数名を書かない。
mapper_name=${REMOVABLE_CRYPT_NAME:?is not set}

if [[ ! -w /dev/mapper/control ]]; then
  echo "error: no permission to access /dev/mapper/control (use sudo)" >&2
  exit 1
fi

mount_point="/mnt/$mapper_name"
has_error=0

# btrfs: create snapshot before unmount
if [[ -e "/dev/mapper/$mapper_name" ]]; then
  fs_type=$(blkid -s TYPE -o value "/dev/mapper/$mapper_name" 2>/dev/null || true)
  if [[ $fs_type == "btrfs" ]]; then
    if ! snapper -c "$mapper_name" create \
      --cleanup-algorithm timeline --description "unmount"; then
      echo "warning: failed to create snapshot for $mapper_name" >&2
      has_error=1
    fi
  fi
fi

if ! umount "$mount_point"; then
  echo "warning: failed to unmount $mount_point" >&2
  has_error=1
fi

if [[ -d $mount_point ]]; then
  if ! rmdir "$mount_point"; then
    echo "warning: failed to remove $mount_point" >&2
    has_error=1
  fi
fi

if [[ -e "/dev/mapper/$mapper_name" ]]; then
  if ! systemd-cryptsetup detach "$mapper_name"; then
    echo "warning: failed to detach $mapper_name" >&2
    has_error=1
  fi
fi

exit "$has_error"
