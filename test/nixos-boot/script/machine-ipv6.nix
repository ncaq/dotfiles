# コンテナとmicroVMがIPv6で外へ出るための土台が、
# `machine-egress`の許可リストとは別に揃っていることを確認します。
# 許可リストはfilterテーブルのルールの形しか見ないので、
# NATモジュールの`enableIPv6`が外れてIPv6のmasqueradeが消えても、
# vethやTAPへのULAの付与が設定から抜けても通ってしまいます。
#
# 以下を見ます。
#
# - IPv6のNATテーブルにmasqueradeがあること
# - IPv6アドレスを持つコンテナの設定ファイルに、ホスト側とコンテナ側のIPv6アドレスが書かれていること。
#   コンテナのinitとホスト側のpostStartはこのファイルを読んでアドレスと経路を付けます
# - ホスト側のsystemd-networkdの設定ファイルに、宣言したIPv6アドレスが書かれていること。
#   `lib/container-veth.nix`とmicroVMのTAPはpostStartではなくこちらで付けます
# - microVMのTAPに実際にIPv6アドレスが付くこと
#
# コンテナのvethは実際のインターフェイスを見ません。
# テストVMでは秘密情報が無いので大半のコンテナが起動に失敗して、
# vethが作られないからです。
#
# microVMは、テストVMでも起動するものだけ実際のインターフェイスを見ます。
# 起動しないmicroVMも、networkdの設定ファイルの検査の対象には入っています。
#
# TAPの名前はVMの名前から導かず、VMの`microvm.interfaces`から引きます。
# インターフェイス名は15文字までなので、VMの名前より短い名前を付けることがあります。
{
  lib,
  pkgs,
  config,
  startsInTestVm,
  ...
}:
let
  nft = lib.getExe' pkgs.nftables "nft";
  inherit (config.networking) nat;
  ipv6Containers = lib.filterAttrs (_: c: c.hostAddress6 != null) config.containers;
  isIpv6 = address: lib.hasInfix ":" address;
  ipv6Networks = lib.filterAttrs (
    _: n: lib.any (a: isIpv6 a.Address) n.addresses
  ) config.systemd.network.networks;
  ipv6VmTaps = lib.filter (t: ipv6Networks ? "20-${t.tap}") (
    lib.concatLists (
      lib.mapAttrsToList (
        name: vm:
        map (interface: {
          inherit name;
          tap = interface.id;
        }) (lib.filter (interface: interface.type == "tap") vm.config.config.microvm.interfaces)
      ) (lib.filterAttrs (name: _: startsInTestVm name) (config.microvm.vms or { }))
    )
  );
in
lib.optionalString (nat.enable && nat.enableIPv6) # python
  ''
    machine.wait_for_unit("nftables.service")
    nat6 = machine.succeed("${nft} list table ip6 nixos-nat")
    assert "masquerade" in nat6, nat6
  ''
+ lib.concatStrings (
  lib.mapAttrsToList (
    name: c: # python
    ''
      container_conf = machine.succeed("cat /etc/nixos-containers/${name}.conf")
      assert "HOST_ADDRESS6=${c.hostAddress6}" in container_conf, container_conf
      assert "LOCAL_ADDRESS6=${c.localAddress6}" in container_conf, container_conf
    '') ipv6Containers
)
+ lib.concatStrings (
  lib.mapAttrsToList (
    name: n:
    lib.concatMapStrings (
      a: # python
      ''
        machine.succeed("grep -qF 'Address=${a.Address}' /etc/systemd/network/${name}.network")
      '') (lib.filter (a: isIpv6 a.Address) n.addresses)
  ) ipv6Networks
)
+ lib.concatMapStrings (
  t:
  lib.concatMapStrings (
    a: # python
    ''
      machine.wait_for_unit("microvm@${t.name}.service")
      machine.wait_until_succeeds("ip -6 addr show dev ${t.tap} | grep -qF '${a.Address}'")
    '') (lib.filter (a: isIpv6 a.Address) ipv6Networks."20-${t.tap}".addresses)
) ipv6VmTaps
