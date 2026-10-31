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
  # exit nodeの広告も含めてここで宣言する。
  # `--advertise-routes`は広告する経路を丸ごと置き換えるフラグで、
  # exit nodeの広告も内部的には`0.0.0.0/0`と`::/0`の経路として同じリストに入るため、
  # `--advertise-exit-node`を一緒に指定しないとexit nodeの広告が消える。
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
  # 経路は`networking.hosts`で名前を向けているアドレスだけを`/32`で広告する。
  # Caddyはniks3-privateのホスト側アドレスにもbindしているが、
  # そこへ向けている名前は無いので広告しない。
  # `/24`で広告すると承認した途端にコンテナ側のアドレスまでexit node経由の端末から見えるようになるので、
  # 必要な2つに絞る。
  services.tailscale.extraSetFlags = [
    "--advertise-exit-node"
    "--advertise-routes=${garageHostAddr}/32,${niks3PublicHostAddr}/32"
  ];
}
