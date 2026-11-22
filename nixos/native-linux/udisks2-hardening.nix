# udisks2のユニットへ、仕事と関係の無い範囲だけハードニングを足す。
#
# udisks2はfwupdのモジュールが有効にしていて、
# ディスクのマウントやフォーマットをユーザの代わりにrootで行う。
# 上流のユニットもnixpkgsのモジュールも何も絞っていない。
#
# マウントした結果はホストの側から見えないと意味が無い。
# systemdのファイルシステムの保護はどれもユニットを専用のマウント名前空間へ入れるので、
# 1つでも付けると、udisks2のマウントがホストへ伝わらなくなる。
# エラーにはならず、マウントに成功したと返ってくるのに中身が見えない形で壊れる。
# そのため以下は付けていない。
#
# - `ProtectSystem`と`ProtectHome`と`PrivateTmp`と`PrivateDevices`
# - `ProtectKernelTunables`と`ProtectKernelModules`と`ProtectKernelLogs`と`ProtectControlGroups`
# - `ProtectHostname`
#
# 他に付けていないもの。
#
# - `ProtectClock`: デバイスを許可リスト方式へ切り替える副作用があり、ディスクを開けなくなる
# - `CapabilityBoundingSet`: マウントやフォーマットやモジュールの読み込みで広く要る
# - システムコールの`@mount`と`@swap`の禁止: マウントとスワップの有効化が仕事に含まれる
#
# 残るのは、名前空間を作らずにseccompなどで効くものだけになる。
{ lib, config, ... }:
{
  config = lib.mkIf config.services.udisks2.enable {
    systemd.services.udisks2.serviceConfig = {
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = [
        # D-Bus。
        "AF_UNIX"
        # udevのイベントを受ける。
        "AF_NETLINK"
      ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [
        "~@clock"
        "~@cpu-emulation"
        "~@debug"
        "~@obsolete"
        "~@reboot"
      ];
    };
  };
}
