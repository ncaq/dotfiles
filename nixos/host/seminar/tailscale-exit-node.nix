{ config, ... }:
let
  garageHostAddr = config.machineAddresses.garage.host;
  niks3PublicHostAddr = config.machineAddresses.niks3-public.host;
in
{
  # seminarをexit nodeとして広告する。
  #
  # exit nodeとしての広告は以前は`tailscale set --advertise-exit-node`で手で設定していた。
  # サブネットルートを足す必要が出たので、
  # `tailscale set`は広告する経路を丸ごと置き換える仕様に合わせて、
  # exit nodeの広告も含めてここで宣言する。
  #
  # exit node経由の端末がseminarのCaddyへ届くための経路も一緒に広告する。
  # `caddy.nix`の`networking.hosts`で`niks3-public.ncaq.net`と`garage.ncaq.net`を、
  # コンテナのvethのホスト側アドレスへ向けているが、
  # この名前の解決結果はexit node経由の端末にもそのまま返る。
  # tailscaledは`0.0.0.0/0`を広告する時、
  # 自分のインターフェースに直接繋がっているLANの範囲を、
  # わざとパケットフィルタの対象から外す。
  # ゲストWi-Fiのようにインターネットだけを提供して、
  # LANへも通したい時はそのLANを別途サブネットルートとして広告させる設計になっている。
  # vethのホスト側アドレスはこの除外に当たるため、
  # tailnetのACLで宛先を許可していてもseminarのtailscaledが捨てる。
  # 広告する経路に該当アドレスを明示的に足して、
  # フィルタの対象に戻す。
  #
  # 広告した経路はtailnet側で承認されないと有効にならない。
  # 承認とACLはinfra.ncaq.netの`tailscale/subnet-route.tf`と`tailscale/access-policy.tf`にあり、
  # そちらのアドレスはここと同じ値を手で揃えている。
  #
  # 経路はCaddyがbindしているアドレスだけを`/32`で広告する。
  # `/24`で広告すると承認した途端にコンテナ側のアドレスまでexit node経由の端末から見えるようになるので、
  # 必要な2つに絞る。
  services.tailscale.extraSetFlags = [
    "--advertise-exit-node"
    "--advertise-routes=${garageHostAddr}/32,${niks3PublicHostAddr}/32"
  ];
}
