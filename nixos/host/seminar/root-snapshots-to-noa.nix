{ pkgs, ... }:
let
  # 転送元のrootに残す世代の上限。
  # 古い世代はnoaに残るので、SSDの上では他のホストより少なくする。
  # 転送先に残す世代の下限にも同じ値を使う。
  # 転送元に残っている世代を転送先で消すと、
  # snbkは足りないものとして次の回に転送し直すので、
  # 消しては送り直すことを毎日繰り返してしまう。
  rootLimit = {
    hourly = 10;
    daily = 7;
    monthly = 2;
    yearly = 2;
  };
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
  # 上流のユニットはcapabilityなどを既に選んで絞っているので、そこは変えずに足りない分を足す。
  # 転送先は`target-mode = "local"`でネットワークを使わず、
  # snapperdとはD-Busで話すので、UNIXソケット以外を閉じる。
  # 内容は`lib/systemd-hardening.nix`の`unixSocket`から以下を除いたもの。
  #
  # - `ProtectSystem`:
  #   転送先を`ReadWritePaths`で開けるとマウントが増えて、
  #   `btrfs receive`がサブボリュームを辿れずに失敗する
  # - `CapabilityBoundingSet`と`NoNewPrivileges`: 上流の指定を残す
  # - `PrivateDevices`と`RestrictSUIDSGID`と`ProtectKernelModules`:
  #   上流が残している`CAP_MKNOD`と`CAP_FSETID`と`CAP_SYS_MODULE`を落としたり無効にしたりする。
  #   スナップショットの中のデバイスファイルやsetuidされたファイルを復元できなくなる
  #
  # `ProtectHome`は上流が`WorkingDirectory=/root`にしているので読み取り専用に留める。
  # `lowPriority`と同じ理由で`[Service]`セクションを追記する。
  hardeningText = ''

    [Service]
    MemoryDenyWriteExecute=true
    PrivateNetwork=true
    PrivateTmp=true
    ProtectClock=true
    ProtectControlGroups=true
    ProtectHome=read-only
    ProtectKernelLogs=true
    ProtectKernelTunables=true
    RestrictAddressFamilies=AF_UNIX
    RestrictNamespaces=true
    SystemCallArchitectures=native
    SystemCallFilter=@system-service
  '';
  # 転送先は`/mnt/noa/backup-snapshots/<hostname>/<config>`で名前空間を切る。
  # snbkが転送先に作る`<番号>/info.xml`と`<番号>/snapshot`は、
  # snapperの`.snapshots`の中身と同じ形をしている。
  # 転送先の名前を`.snapshots`にすると、
  # 親の`backupSubvolume`を`SUBVOLUME`とするsnapperのconfigから見えるので、
  # 転送先に残す世代をsnapperのtimeline cleanupに決めさせられる。
  backupSubvolume = "/mnt/noa/backup-snapshots/seminar/root";
  targetPath = "${backupSubvolume}/.snapshots";
  # snbkには転送元に無いスナップショットを消す`delete`しか無く、
  # `transfer-and-delete`だと転送先は転送元の鏡にしかならない。
  # 転送先はHDDで広いので、転送元より古い世代まで残したい。
  # 転送だけを行わせて、消すのは下の`noa-backup-seminar-root`のconfigに任せる。
  # `lowPriority`と同じ理由で`[Service]`セクションを追記する。
  # 空の代入で上流の`ExecStart`を消してから指定する。
  transferOnly = ''

    [Service]
    ExecStart=
    ExecStart=${pkgs.snapper}/sbin/snbk --verbose --automatic transfer
  '';
  # 上流のtimerは1時間ごとに転送する。
  # 新しい世代は転送元のSSDにも残っていて、
  # 転送先に欲しいのは古い世代なので、1日に1回で足りる。
  # 0時ちょうどはその日の最初のスナップショットを作っている最中なので、少しずらす。
  # 空の代入で上流の`OnCalendar`を消してから指定する。
  dailyTimer = ''

    [Timer]
    OnCalendar=
    OnCalendar=*-*-* 00:30:00
  '';
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
  environment.etc."snapper/backup-configs/seminar-root.json".text = builtins.toJSON {
    config = "root";
    target-mode = "local";
    automatic = true;
    source-path = "/";
    target-path = targetPath;
  };

  systemd = {
    # snapper同梱のbackup unitを流用して、実行するコマンドと頻度だけを変える。
    units = {
      "snapper-backup.service".text =
        builtins.readFile "${pkgs.snapper}/lib/systemd/system/snapper-backup.service"
        + transferOnly
        + lowPriority
        + keepRunningOnSwitch
        + hardeningText
        + requireMount;
      "snapper-backup.timer" = {
        text = builtins.readFile "${pkgs.snapper}/lib/systemd/system/snapper-backup.timer" + dailyTimer;
        wantedBy = [ "timers.target" ];
      };
    };
    # snapperは`SUBVOLUME`と、その中の`.snapshots`の両方がbtrfsのサブボリュームであることを求める。
    # `v`はbtrfsの上ならサブボリュームを作る。
    # 一番上の`backup-snapshots`はdiskoでも宣言しているが、
    # diskoはフォーマットの時にしか作らないので、ここでも作る。
    # 権限は元の`.snapshots`に合わせている。
    tmpfiles.rules = [
      "v /mnt/noa/backup-snapshots 0755 root root -"
      "d /mnt/noa/backup-snapshots/seminar 0755 root root -"
      "v ${backupSubvolume} 0755 root root -"
      "v ${targetPath} 0755 root root -"
    ];
  };

  services.snapper.configs = {
    # 転送元。
    # 全ホストに共通のrootの設定は`nixos/native-linux/snapper.nix`にある。
    # seminarだけ上限を`rootLimit`へ下げる。
    # hourlyとdailyの下限は共通の設定と同じ2のままにする。
    # monthlyとyearlyは古い世代がnoaにあるので、
    # 空き容量が逼迫した時はSSDの上から全て消してよい。
    root = {
      TIMELINE_LIMIT_HOURLY = "2-${toString rootLimit.hourly}";
      TIMELINE_LIMIT_DAILY = "2-${toString rootLimit.daily}";
      TIMELINE_LIMIT_MONTHLY = "0-${toString rootLimit.monthly}";
      TIMELINE_LIMIT_YEARLY = "0-${toString rootLimit.yearly}";
    };

    # 転送先に残す世代を決める。
    # スナップショットは作らず、snbkが転送してきたものを掃除するだけ。
    # 転送されたスナップショットの`info.xml`は転送元と同じで、
    # timelineの掃除対象の印が付いている。
    noa-backup-seminar-root = {
      SUBVOLUME = backupSubvolume;

      TIMELINE_CREATE = false;
      TIMELINE_CLEANUP = true;

      # 下限を`rootLimit`にしている理由は`rootLimit`に書いている。
      # hourlyは古い世代を残す意味が薄いので転送元と同じにして、
      # それ以外を長く残す。
      TIMELINE_LIMIT_HOURLY = toString rootLimit.hourly;
      TIMELINE_LIMIT_DAILY = "${toString rootLimit.daily}-30";
      TIMELINE_LIMIT_MONTHLY = "${toString rootLimit.monthly}-36";
      TIMELINE_LIMIT_YEARLY = "${toString rootLimit.yearly}-10";

      # 空き容量が逼迫した時に世代数の下限まで追加で削除する。
      # 範囲指定が必要な理由やSPACE_LIMITを使わない理由は、
      # rootの設定がある`nixos/native-linux/snapper.nix`に書いている。
      FREE_LIMIT = "0.2";
    };
  };
}
