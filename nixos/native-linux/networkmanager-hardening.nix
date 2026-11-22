# NetworkManagerのユニットへ、仕事と関係の無い範囲だけハードニングを足す。
#
# 上流のユニットはcapabilityと`ProtectSystem=true`と`ProtectHome=read-only`しか絞っていない。
# NetworkManagerはリンクの設定そのものが仕事なので、
# `lib/systemd-hardening.nix`をそのまま被せると壊れる。
# 外向きのリンクを全て任せていて、壊すとホストへ届かなくなるので、
# 何をしているかに関わらず要らないと言えるものだけを選ぶ。
#
# 以下はあえて付けていない。
#
# - `ProtectClock`:
#   デバイスを許可リスト方式へ切り替える副作用があり、
#   `/dev/rfkill`や`/dev/net/tun`を開けなくなる
# - `ProtectKernelTunables`: インタフェースごとのsysctlを`/proc/sys/net`へ書き込めなくなる
# - `ProtectKernelModules`: 上流が`CAP_SYS_MODULE`を残している
# - `ProtectHostname`: DHCPで受け取ったホスト名を設定できなくなる
# - `RestrictNamespaces`: ネットワーク名前空間を切り替えるコードを持っている
# - `RestrictAddressFamilies`:
#   netlinkやpacketの他にBluetoothなども使い、接続の種類ごとに要るものが変わる
# - `ProtectSystem=strict`と`PrivateDevices`と`ProtectProc`:
#   書き込む場所と開くデバイスと参照する他のプロセスが多い
{ lib, config, ... }:
{
  config = lib.mkIf config.networking.networkmanager.enable {
    systemd.services.NetworkManager.serviceConfig = {
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectControlGroups = true;
      ProtectKernelLogs = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      # 許可リストにすると接続の種類ごとの差を拾い切れないので、
      # ネットワークの管理では使わない種類だけを禁止する。
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
