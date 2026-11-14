# コンテナとmicroVMからの転送の許可リスト(`nixos/native-linux/machine-egress.nix`)が、
# 実際に読み込まれていて、宣言した通りの形になっていることを確認します。
# この境界はテーブルが消えても残りのルールセットは問題なく読み込まれるので静かに消えます。
#
# 発火条件は守りたいもの(出口を絞るべきマシンがある)にして、
# 守り方(テーブルの有無)には連動させません。
# テーブル名は設定から直接参照するので、
# テーブルが消えればこの検査ごと消えるのではなく、
# 属性が無いという評価エラーで止まります。
#
# 独立したベースチェインなので他のチェインとの並び順は関係ありません。
# 代わりに以下を見ます。
#
# - NATが転送を通すインターフェイスからのパケットが許可リストのチェインへ飛ぶこと
# - `internet`から除く集合に、LANとDNAT後のコンテナを含む`192.168.0.0/16`とtailnetの範囲が入っていること
# - IPv6で`internet`から除く集合に、tailnetと他のコンテナを含むULA全体とリンクローカルが入っていること
# - 各マシンのacceptが宣言した宛先の数だけあり、`internet`はIPv4とIPv6の1つずつで除く集合の否定で書かれていること
# - 宣言した宛先はIPv6の`ip6 daddr`で許されていること。
#   マシン同士はIPv6で繋ぐので、`ip daddr`に戻ると宛先へ届かなくなります。
#   宛先の型は省略しない書き方や大文字も受け付け、nftは省略した小文字で出力するので、
#   文字列ではなくアドレスの値として比べます
# - 各マシンのルールの末尾と、チェイン全体の末尾がdropであること
{
  lib,
  pkgs,
  config,
  ...
}:
let
  nft = lib.getExe' pkgs.nftables "nft";
  machineEgress = config.local.machineEgress or { };
in
lib.optionalString (machineEgress != { }) (
  # python
  ''
    machine.wait_for_unit("nftables.service")
    egress_table = "${config.networking.nftables.tables.machine-egress.name}"

    egress_forward = machine.succeed(f"${nft} list chain inet {egress_table} forward")
    assert "jump egress" in egress_forward, egress_forward

    private_networks = machine.succeed(f"${nft} list set inet {egress_table} private-networks")
    for prefix in ["192.168.0.0/16", "${config.local.tailscale.ipv4Range}"]:
        assert prefix in private_networks, private_networks

    private_networks6 = machine.succeed(f"${nft} list set inet {egress_table} private-networks6")
    for prefix in ["fc00::/7", "fe80::/10"]:
        assert prefix in private_networks6, private_networks6

    egress = machine.succeed(f"${nft} list chain inet {egress_table} egress")
    # テーブルとチェインの枠を除いたルールの行だけにします。
    egress_rules = [
        line.strip()
        for line in egress.splitlines()
        if line.strip() and not line.strip().startswith(("table ", "chain ", "}"))
    ]
    assert "drop" in egress_rules[-1].split(), egress

    import ipaddress

    def ip6_daddrs(rules):
        """ルールの行の`ip6 daddr`の直後に書かれたアドレスを値として読みます。

        `ip6 daddr != @private-networks6`のようにアドレスでないものは飛ばします。
        """
        addresses = []
        for rule in rules:
            tokens = rule.split()
            for i in range(len(tokens) - 2):
                if tokens[i] == "ip6" and tokens[i + 1] == "daddr":
                    try:
                        addresses.append(ipaddress.IPv6Address(tokens[i + 2]))
                    except ValueError:
                        pass
        return addresses
  ''
  + lib.concatMapStrings (
    m: # python
    ''
      machine_rules = [r for r in egress_rules if 'iifname "${m.interface}"' in r]
      machine_accepts = [r for r in machine_rules if "accept" in r.split()]
      assert len(machine_accepts) == ${
        toString (lib.length m.destinations + (if m.internet then 2 else 0))
      }, machine_rules
      # 集合名は空白で区切られたトークンとして照合します。
      # 部分文字列で見ると`@private-networks`が`@private-networks6`にも一致します。
      assert ${if m.internet then "" else "not "}any(
          "@private-networks" in r.split() for r in machine_accepts
      ), machine_rules
      assert ${if m.internet then "" else "not "}any(
          "@private-networks6" in r.split() and "nexthop fe80::/10" in r for r in machine_accepts
      ), machine_rules
      assert "drop" in machine_rules[-1].split(), machine_rules
      machine_daddrs = ip6_daddrs(machine_accepts)
    ''
    + lib.concatMapStrings (
      d: # python
      ''
        assert ipaddress.IPv6Address("${d.address}") in machine_daddrs, machine_rules
      '') m.destinations
  ) (lib.attrValues machineEgress)
)
