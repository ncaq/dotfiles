{ lib, config, ... }:
let
  lan = config.local.lan;
  rule = config.local.ssh.firewallRule;
  tcpPorts = lib.concatMapStringsSep ", " toString rule.allowedTCPPorts;
  udpRanges = lib.concatMapStringsSep ", " (
    r: "${toString r.from}-${toString r.to}"
  ) rule.allowedUDPPortRanges;
in
{
  # サーバはヘッドレス運用なので、tailscaledが故障した時の復旧経路として、
  # tailnet限定(`nixos/core/ssh.nix`)に加えてLANからのssh/moshも受け付ける。
  #
  # 全インターフェイスに開けるのではなくLANのインターフェイスに限定するのは、
  # コンテナのvethやmicroVMのTAPからホストのsshdへ届かせないため。
  # CIランナーのようにリポジトリのコードが動くコンテナから、
  # 認証が必要とはいえホストのSSHに触れる理由は無い。
  #
  # インターフェイスだけでなく送信元アドレスでも絞る(`samba.nix`と同じ理由)。
  # IPv4はルータのNATの内側なのでインターフェイス単位の許可でもLANの外からは届かないが、
  # LANのインターフェイスにはグローバルIPv6アドレスも付いていて、
  # ルータのIPv6のフィルタに頼らない限りインターネットからそこへ届く経路を塞げない。
  # 鍵認証しか通らないとはいえ、復旧経路をインターネットに晒す理由は無い。
  # LANのIPv6はリンクローカルだけ許す。
  # 復旧はIPv4のアドレスを直接指定して繋ぐ想定で、
  # グローバルIPv6を引いてしまう`seminar.local`のような名前はIPv4へ倒れるまで待たされる。
  #
  # `local.lan`はseminarの`lan.nix`が宣言しているオプションで、
  # server層を取り込むホストは今のところseminarだけなのでそのまま参照する。
  networking.firewall.extraInputRules = ''
    iifname "${lan.interface}" ip saddr ${lan.ipv4Subnet} tcp dport { ${tcpPorts} } accept comment "ssh from LAN"
    iifname "${lan.interface}" ip saddr ${lan.ipv4Subnet} udp dport { ${udpRanges} } accept comment "mosh from LAN"
    iifname "${lan.interface}" ip6 saddr fe80::/10 tcp dport { ${tcpPorts} } accept comment "ssh from LAN link-local IPv6"
    iifname "${lan.interface}" ip6 saddr fe80::/10 udp dport { ${udpRanges} } accept comment "mosh from LAN link-local IPv6"
  '';
}
