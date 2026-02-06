{ pkgs, ... }:
{
  # WindowsでマウントされたネットワークドライブをWSL側で自動マウントする
  systemd.services.mount-windows-network-drives = {
    description = "Mount Windows network drives in WSL";
    after = [ "local-fs.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Sドライブをマウント (Windows側で\\SEMINAR\chihiroが割り当てられている)
      # 以下のようにWindows側で共有ディレクトリをSドライブに割り当てておく必要があります
      # ```
      # net use S: \\SEMINAR\chihiro /persistent:yes
      # ```
      ExecStart = "${pkgs.util-linux}/bin/mount -t drvfs 'S:' /mnt/s -o metadata,uid=1000,gid=100";
      ExecStop = "${pkgs.util-linux}/bin/umount /mnt/s";
    };
  };

  # マウントポイントのディレクトリを事前に作成
  systemd.tmpfiles.rules = [
    "d /mnt/s 0755 root root -"
  ];
}
