# NetworkManagerのdispatcherのユニットへ、控えめなハードニングを足す。
#
# dispatcherは接続の状態が変わるたびに、登録されたスクリプトをrootで実行する。
# 上流のユニットもnixpkgsのモジュールも何も絞っていない。
# 実行されるのは自分で書いて登録したプログラムだけで、
# 今は`wifi-wired-exclusive`と`tailscale-exit-node`がある。
# どちらも`nmcli`や`tailscale`でデーモンへ頼むだけで、自分では特権を使わない。
#
# 何を実行するかは決まっていないので、許可するものを並べる形にはしない。
# 接続の変化に反応するスクリプトが常識的には使わないものだけを禁止する。
# `systemctl`でのサービスの操作のようにデーモンへ頼む処理は、
# 頼む側の権限を絞っても影響を受けない。
#
# ファイルシステムの保護(`ProtectSystem`や`PrivateTmp`など)は付けていない。
# どれもユニットを専用のマウント名前空間へ入れるので、
# スクリプトがネットワーク越しの共有をマウントしても、ホストへ伝わらなくなる。
# エラーにならずに見えないだけなので、後から書くスクリプトで気付きにくい。
# 同じ理由で`RestrictNamespaces`も付けていない。`ip netns`を使えなくなる。
#
# ここで禁止したものが要るスクリプトを足す時は、このファイルを見直すこと。
{ lib, config, ... }:
{
  config = lib.mkIf config.networking.networkmanager.enable {
    systemd.services.NetworkManager-dispatcher.serviceConfig = {
      # 先頭の`~`で、並べたものを落として残りを許す。
      CapabilityBoundingSet = [
        "~CAP_AUDIT_CONTROL"
        "~CAP_BLOCK_SUSPEND"
        "~CAP_LINUX_IMMUTABLE"
        "~CAP_MAC_ADMIN"
        "~CAP_MAC_OVERRIDE"
        "~CAP_MKNOD"
        "~CAP_SYS_BOOT"
        "~CAP_SYS_PACCT"
        "~CAP_SYS_PTRACE"
        "~CAP_SYS_RAWIO"
        "~CAP_SYS_TIME"
        "~CAP_SYS_TTY_CONFIG"
        "~CAP_SYSLOG"
        "~CAP_WAKE_ALARM"
      ];
      LockPersonality = true;
      # JITを持つ処理系で書いたスクリプトは動かなくなる。
      MemoryDenyWriteExecute = true;
      NoNewPrivileges = true;
      # ネットワークの操作に使う範囲。
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_NETLINK"
        "AF_PACKET"
        "AF_UNIX"
      ];
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [
        "~@clock"
        "~@cpu-emulation"
        "~@debug"
        "~@obsolete"
        "~@raw-io"
        "~@reboot"
        "~@swap"
      ];
    };
  };
}
