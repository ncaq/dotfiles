# TODO: noa2(WD121PURZ)が2026-11-14にSATAリンクから脱落したための一時的な措置。
# 障害対応が終わったら、このファイルごと消す。
# その時は`disk.nix`で足した`/mnt/noa`の`degraded`も一緒に外す。
# https://github.com/ncaq/dotfiles/issues/1732
#
# systemdの`64-btrfs.rules`は複数デバイスのbtrfsの全メンバが揃うまで、
# メンバのデバイスを`SYSTEMD_READY=0`にする。
# `/mnt/noa`のマウントオプションに`degraded`を付けていても、
# マウントユニットが`dev-mapper-noa0.device`を待ってタイムアウトし、自動でマウントされない。
# そこで`/mnt/noa`のマウント元である`noa0`だけは、全メンバが揃っていなくてもreadyとみなす。
#
# noa0とnoa1はinitrdで解錠され、その時点でinitrdのudevがbtrfsのデバイスとしてカーネルに登録する。
# なのでstage 2でマウントする時には、残っているメンバは登録済みになっている。
#
# この措置がある間は、メンバが欠けても黙ってdegradedでマウントされる。
# `btrfs filesystem show /mnt/noa`でMISSINGが無いかを気にかけること。
{ pkgs, ... }:
{
  services.udev.packages = [
    (pkgs.writeTextDir "lib/udev/rules.d/65-noa-btrfs-degraded.rules" ''
      SUBSYSTEM=="block", ACTION!="remove", ENV{DM_NAME}=="noa0", ENV{ID_FS_TYPE}=="btrfs", ENV{ID_BTRFS_READY}=="0", ENV{SYSTEMD_READY}="1"
    '')
  ];
}
