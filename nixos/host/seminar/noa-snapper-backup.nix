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
  # 転送の最中に設定を適用してユニットが変更扱いになっても、
  # 途中で止められてやり直しにならないようにする。
  # タイマーで起動するので、次の回は新しい定義で動く。
  # `lowPriority`と同じ理由で、
  # `restartIfChanged = false`が生成するものと同じ指定を追記する。
  keepRunningOnSwitch = ''

    [Service]
    X-RestartIfChanged=false
  '';
  targetPath = "/mnt/noa/snapshot-backup/seminar/root";
  # `/mnt/noa`は`nofail`なので、
  # マウントに失敗してもブートは進みます。
  # マウントされていない時に転送すると、
  # ルートのSSDの上の空のディレクトリへrootのスナップショットを丸ごと書き込むので、
  # マウントを必須にします。
  # `lowPriority`と同じ理由で`[Unit]`セクションを追記します。
  requireMount = ''

    [Unit]
    RequiresMountsFor=${targetPath}
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
    target-path = targetPath;
  };

  systemd = {
    # snapper同梱のbackup unitをそのまま流用する。
    # serviceは`snbk --verbose --automatic transfer-and-delete`を実行し、
    # `automatic: true`のbackup-configを転送しつつリテンションに基づく削除も行う。
    units = {
      "snapper-backup.service".text =
        builtins.readFile "${pkgs.snapper}/lib/systemd/system/snapper-backup.service"
        + lowPriority
        + keepRunningOnSwitch
        + requireMount;
      "snapper-backup.timer" = {
        text = builtins.readFile "${pkgs.snapper}/lib/systemd/system/snapper-backup.timer";
        wantedBy = [ "timers.target" ];
      };
    };
    # target-path配下のディレクトリを用意する。
    # サブボリューム自体はdiskoで管理している。
    # 権限は元の`.snapshots`の典型的形式に合わせています。
    tmpfiles.rules = [
      "d /mnt/noa/snapshot-backup/seminar 0755 root root -"
      "d /mnt/noa/snapshot-backup/seminar/root 0755 root root -"
    ];
  };
}
