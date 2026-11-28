# クライアントは`nixos/client/cifs.nix`でchihiro共有を`/mnt/chihiro`にマウントします。
# seminarでも同じパスでアクセスできるように、共有の実体へのシンボリックリンクを作成します。
{
  systemd.tmpfiles.rules = [
    "L+ /mnt/chihiro - - - - /mnt/noa/chihiro/"
  ];
}
