{
  pkgs,
  lib,
  config,
  hardening,
  ...
}:
let
  days = config.local.trash.retentionDays;
  trashHardening =
    # 全ユーザのホーム、全マウント先、ホストの/tmpにあるゴミ箱を掃除するため、
    # それらを不可視またはread-onlyにする隔離は適用できない。
    removeAttrs hardening.isolated [
      "PrivateTmp"
      "ProtectHome"
      "ProtectSystem"
    ]
    // {
      # rootが他ユーザ所有のゴミ箱を走査・削除するために必要な権限だけを残す。
      CapabilityBoundingSet = [
        "CAP_DAC_OVERRIDE"
        "CAP_FOWNER"
      ];
    };
  # ゴミ箱の掃除は緊急性がないため、他の処理を最優先する。
  lowPriority = {
    Nice = 19;
    CPUSchedulingPolicy = "idle";
    IOSchedulingClass = "idle";
    IOWeight = 10;
  };
  dailyTimer = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
  # `trash-empty-stray`がゴミ箱を探す起点。
  #
  # ユーザのデータを置く場所を全て探す。
  # 起点と違うデバイスのディレクトリへは降りないので、
  # /mntの下にマウントするローカルのディスクは起点として別に渡す。
  # ネットワークマウントは実体のあるホストの側で掃除するので、ここへは入れない。
  # `/mnt/chihiro`のようなCIFSのマウントは`systemd.mounts`で定義しているので、元から`fileSystems`に無い。
  #
  # マウントしていない入れ子のbtrfsサブボリュームの直下に作られたゴミ箱は対象外になる。
  # 親と違うデバイスに見えるので降りず、マウントの定義も無いので起点にも入らない。
  localDiskTypes = [
    "btrfs"
    "exfat"
    "ext4"
    "vfat"
    "xfs"
  ];
  strayRoots = [
    "/efi"
    "/home"
    "/mnt"
  ]
  ++ lib.sort lib.lessThan (
    lib.mapAttrsToList (_: fileSystem: fileSystem.mountPoint) (
      lib.filterAttrs (
        _: fileSystem:
        lib.hasPrefix "/mnt/" fileSystem.mountPoint && lib.elem fileSystem.fsType localDiskTypes
      ) config.fileSystems
    )
  );
in
{
  options.local.trash.retentionDays = lib.mkOption {
    type = lib.types.ints.positive;
    default = 7;
    description = ''
      ゴミ箱へ入れてからこの日数が経ったものを消す。
      Sambaのゴミ箱のように別の仕組みで掃除するものも、保持期間が食い違わないようにここを参照する。
    '';
  };

  config.systemd = {
    services = {
      trash-empty = {
        description = "Remove files older than ${toString days} days from all trash cans";
        after = [
          "local-fs.target"
          "remote-fs.target"
        ];
        serviceConfig =
          trashHardening
          // lowPriority
          // {
            Type = "oneshot";
            TimeoutStartSec = "1h";
            ExecStart = "${pkgs.trash-cli}/bin/trash-empty --all-users -f ${toString days}";
          };
      };
      # `trash-empty --all-users`が見つけられないゴミ箱を探して掃除する。
      # 何を探してどう掃除するかは`pkgs/trash-empty-stray`に書いてある。
      #
      # `trash-empty`とはユニットを分ける。
      # 片方が失敗してももう片方は動き、失敗はそれぞれのユニットの結果に出る。
      trash-empty-stray = {
        description = "Remove files older than ${toString days} days from stray trash cans";
        after = [ "local-fs.target" ];
        serviceConfig =
          trashHardening
          // lowPriority
          // {
            # 見つけたゴミ箱を所有者の権限で掃除するために、uidとgidを変える権限を足す。
            # 一般ユーザのゴミ箱は権限を落として掃除するので、
            # 残りの権限を使うのは探索と、rootが所有するゴミ箱の掃除だけになる。
            CapabilityBoundingSet = trashHardening.CapabilityBoundingSet ++ [
              "CAP_SETGID"
              "CAP_SETUID"
            ];
            Type = "oneshot";
            TimeoutStartSec = "1h";
            ExecStart = lib.escapeShellArgs (
              [
                (lib.getExe pkgs.trash-empty-stray)
                "sweep"
                "--days"
                (toString days)
              ]
              ++ strayRoots
            );
          };
      };
    };
    timers = {
      trash-empty = dailyTimer // {
        description = "Daily trash cleanup";
      };
      trash-empty-stray = dailyTimer // {
        description = "Daily stray trash cleanup";
      };
    };
  };
}
