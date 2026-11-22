# tailscaledのユニットのハードニング。
#
# tailscaledはrootで動いて、tailnetの外からのパケットも直接受ける。
# 上流のユニットもnixpkgsのモジュールも何も絞っていない。
# 上流が絞らないのは、Tailscale SSHを使うとログインしたユーザのシェルがこのユニットの中で動くためで、
# ユニットを制限するとユーザのセッションまで制限される。
# Tailscale SSHは使っておらずOpenSSHで足りているので、ネットワークのデーモンとして絞る。
# Tailscale SSHを有効にする時は、このファイルを外すこと。
#
# 使っている機能は、WireGuardのトンネルとexit nodeとServeとMagicDNSで、
# 必要なのはTUNのデバイスと、経路とフィルタを書き換える権限と、自分の状態のディレクトリになる。
#
# WSLは対象にしていない。
# systemd-resolvedを使わない構成ではtailscaledが`/etc/resolv.conf`を直接書き換えるので、
# `ProtectSystem`と衝突する。
{
  lib,
  config,
  hardening,
  ...
}:
{
  config = lib.mkIf config.services.tailscale.enable {
    systemd.services.tailscaled.serviceConfig =
      removeAttrs hardening.network [
        # TUNのデバイスが要るので、下の`DeviceAllow`で個別に開ける。
        "PrivateDevices"
        # 起動時に`net.ipv4.conf.all.src_valid_mark`を1にする。
        # 付けると`/proc/sys`が読み取り専用になって書けず、警告を出して先へ進んでしまう。
        "ProtectKernelTunables"
      ]
      // {
        CapabilityBoundingSet = [
          # インタフェースと経路とフィルタの設定。
          "CAP_NET_ADMIN"
          # フィルタの設定と、相手の探索に使う生のソケット。
          "CAP_NET_RAW"
          # Serveがtailnetのアドレスの443番で待ち受ける。
          "CAP_NET_BIND_SERVICE"
        ];
        DevicePolicy = "closed";
        DeviceAllow = [
          "/dev/net/tun rw"
          # 端末の情報としてTPMの特性を読む。
          "/dev/tpmrm0 rw"
        ];
        RestrictAddressFamilies = hardening.network.RestrictAddressFamilies ++ [
          # 経路とフィルタの設定。
          "AF_NETLINK"
          # 相手の探索のパケットを生のソケットで受ける。
          "AF_PACKET"
        ];
        # 書き込む先は、上流のユニットが宣言している状態とキャッシュと実行時のディレクトリだけで、
        # それらは`ProtectSystem`の下でも書き込める。
      };
  };
}
