# 自宅LANのインターフェイスへ開けている許可が、
# 全て送信元アドレスでも絞られていることを確認します。
# LANのインターフェイスにはグローバルIPv6アドレスも付いているので、
# インターフェイス単位の許可はインターネットからも届く経路を塞げません。
# `nixos/server/ssh.nix`と`nixos/host/seminar/samba.nix`は送信元で絞っていますが、
# `networking.firewall.interfaces.<lan>`への代入が戻っても、
# `ip6 saddr fe80::/10`が外れても、評価とブートは通ったまま退行します。
#
# 実機のルールセットを見るので、
# どのモジュールがどの形で書いたかに依存せず、
# LANのインターフェイスへ開けた全てのルールをまとめて守れます。
# 発火条件は守りたいもの(`local.lan`を宣言しているホスト)基準にします。
#
# ssh/moshの許可はtailnet側と同じポートの組から来るので、
# IPv4のLANのサブネットとIPv6のリンクローカルの両方の形で存在することも見ます。
{
  lib,
  pkgs,
  config,
  ...
}:
let
  nft = lib.getExe' pkgs.nftables "nft";
  lan = config.local.lan or null;
in
lib.optionalString (lan != null) # python
  ''
    machine.wait_for_unit("nftables.service")
    input_allow = machine.succeed("${nft} list chain inet nixos-fw input-allow")
    lan_rules = [
        line.strip()
        for line in input_allow.splitlines()
        if 'iifname "${lan.interface}"' in line and "dport" in line
    ]
    assert lan_rules, input_allow
    unrestricted = [r for r in lan_rules if "saddr" not in r.split()]
    assert not unrestricted, unrestricted
    for port in ${builtins.toJSON (map toString config.local.ssh.firewallRule.allowedTCPPorts)}:
        assert any(
            f"tcp dport {port}" in r and "ip saddr ${lan.ipv4Subnet}" in r for r in lan_rules
        ), lan_rules
        assert any(
            f"tcp dport {port}" in r and "ip6 saddr fe80::/10" in r for r in lan_rules
        ), lan_rules
  ''
