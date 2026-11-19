# テストVMには実機のNICが無いので、
# systemd-networkdが待つリンクが揃わず、
# `systemd-networkd-wait-online.service`は既定の2分のタイムアウトまで待って失敗します。
# その間`network-online.target`の後ろに並ぶユニットが待たされるだけなので、待たないようにします。
{ lib, ... }:
{
  systemd.network.wait-online.enable = lib.mkForce false;
}
