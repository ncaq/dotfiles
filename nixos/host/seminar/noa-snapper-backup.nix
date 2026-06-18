{ pkgs, ... }:
let
  # snapper.nixの`lowPriority`と同じ意図で、btrfs send/receiveの転送を低優先度にする。
  # snapper-backup.serviceは`systemd.units`の生テキストで定義しているため、
  # `serviceConfig`では上書きできない。
  # 代わりに`[Service]`セクションを追記する。
  # 同一ファイル内の重複セクションはsystemdがマージする。
  lowPriority = ''

    [Service]
    Nice=19
    CPUSchedulingPolicy=idle
    IOSchedulingClass=idle
    IOWeight=10
  '';
in
{
  # snapperが取得済みのrootスナップショットを、
  # snbk(snapper-backup)でnoa(HDD RAID1)へbtrfs send/receive増分転送する。
  # システムドライブ故障時の復旧と、
  # 容量逼迫時の退避先を兼ねる。

  # 転送先は /mnt/noa/snapshot-backup/<hostname>/<config> で名前空間を切る。
  environment.etc."snapper/backup-configs/seminar-root.json".text = builtins.toJSON {
    config = "root";
    target-mode = "local";
    automatic = true;
    source-path = "/";
    target-path = "/mnt/noa/snapshot-backup/seminar/root";
  };

  # snapper同梱のbackup unitをそのまま流用する。
  # serviceは`snbk --verbose --automatic transfer-and-delete`を実行し、
  # `automatic: true`のbackup-configを転送しつつリテンションに基づく削除も行う。
  systemd.units = {
    "snapper-backup.service".text =
      builtins.readFile "${pkgs.snapper}/lib/systemd/system/snapper-backup.service" + lowPriority;
    "snapper-backup.timer" = {
      text = builtins.readFile "${pkgs.snapper}/lib/systemd/system/snapper-backup.timer";
      wantedBy = [ "timers.target" ];
    };
  };

  # target-path配下のディレクトリを用意する。
  # サブボリューム自体はdiskoで管理している。
  systemd.tmpfiles.rules = [
    "d /mnt/noa/snapshot-backup/seminar 0700 root root -"
    "d /mnt/noa/snapshot-backup/seminar/root 0700 root root -"
  ];
}
