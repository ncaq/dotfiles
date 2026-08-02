{ pkgs, hardening, ... }:
let
  trashHardening =
    # 全ユーザーのホーム、全マウント先、ホストの/tmpにあるゴミ箱を掃除するため、
    # それらを不可視またはread-onlyにする隔離は適用できない。
    builtins.removeAttrs hardening.isolated [
      "PrivateTmp"
      "ProtectHome"
      "ProtectSystem"
    ]
    // {
      # rootが他ユーザー所有のゴミ箱を走査・削除するために必要な権限だけを残す。
      CapabilityBoundingSet = [
        "CAP_DAC_OVERRIDE"
        "CAP_FOWNER"
      ];
    };
in
{
  systemd = {
    services.trash-empty = {
      description = "Remove files older than 30 days from all trash cans";
      after = [
        "local-fs.target"
        "remote-fs.target"
        "mnt-chihiro.mount"
      ];
      serviceConfig = trashHardening // {
        Type = "oneshot";
        TimeoutStartSec = "1h";
        ExecStart = "${pkgs.trash-cli}/bin/trash-empty --all-users -f 30";
        # ゴミ箱の掃除は緊急性がないため、他の処理を最優先する。
        Nice = 19;
        CPUSchedulingPolicy = "idle";
        IOSchedulingClass = "idle";
        IOWeight = 10;
      };
    };
    timers.trash-empty = {
      description = "Daily trash cleanup";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
  };
}
