{ lib, config, ... }:
let
  # 経路は`caddy.nix`の`local.caddyInternalHosts`のアドレスから組み立てる。
  # 名前の向き先と経路広告を手で揃える必要を無くすため。
  internalRoutes = map (addr: "${addr}/128") (lib.attrNames config.local.caddyInternalHosts);
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
  # `caddy.nix`の`networking.hosts`で`garage.ncaq.net`を、
  # コンテナのvethのホスト側アドレスへ向けているが、
  # この名前の解決結果はexit node経由の端末にもそのまま返る。
  # tailscaledはexit nodeとして`0.0.0.0/0`と`::/0`を受ける時、
  # 自分のインターフェースに直接繋がっているLANの範囲と、
  # RFC 1918などの予約された範囲を、わざとパケットフィルタの対象から外す。
  # ゲストWi-Fiのようにインターネットだけを提供して、
  # LANへも通したい時はそのLANを別途サブネットルートとして広告させる設計になっている。
  # 向き先がIPv4の192.168.0.0/16だった頃はこの除外に当たり、
  # tailnetのACLで宛先を許可していてもseminarのtailscaledが捨てていた。
  # 今の向き先のIPv6のULAは予約された範囲に入っておらず、
  # 自分のアドレスはLANの範囲を外した後で対象へ戻されるので、除外には当たらない。
  # それでも経路として広告して承認と許可を明示するのは、
  # exit nodeの`::/0`に任せると、
  # 届くかどうかがtailnetのACLの`autogroup:internet`にULAが含まれるかどうかに依存するため。
  #
  # 広告した経路はtailnet側で承認されないと有効にならない。
  # 承認とACLはinfra.ncaq.netの`tailscale/subnet-route.tf`と`tailscale/access-policy.tf`にあり、
  # そちらのアドレスはここと同じ値を手で揃えている。
  #
  # 経路は`local.caddyInternalHosts`で名前を向けているアドレスだけを`/128`で広告する。
  # Caddyはniks3-privateのホスト側アドレスにもbindしているが、
  # そこへ向けている名前は無いので広告しない。
  # `/64`で広告すると承認した途端にコンテナ側のアドレスまでexit node経由の端末から見えるようになるので、
  # 必要なものに絞る。
  services.tailscale.extraSetFlags = [
    "--advertise-exit-node"
    "--advertise-routes=${lib.concatStringsSep "," internalRoutes}"
  ];

  # exit nodeとして使う端末のパケットはtailscale0から入って、
  # LANのインターフェイス(`local.lan.interface`)へ転送される。
  # `filterForward`でforwardチェインのpolicyがdropになっているので、
  # tailscale0からの転送を明示的に許可しないと端末がインターネットへ出られない。
  # tailscaledも自前のテーブルで同じ転送を許可しているが、
  # nftablesでは同じフックの全てのベースチェインを通る必要があり、
  # こちらで落とすとそちらの許可は意味を持たない。
  #
  # 出口はLANのインターフェイスに限定する。
  # 広告しているサブネットルートはvethのホスト側アドレスで、
  # それはINPUTで受けるので転送の出口にはならない。
  # コンテナのvethやmicroVMのTAPへの転送はtailscaledのフィルタとACLが止めているが、
  # こちらでも許可しないことで多層にする。
  networking.firewall.extraForwardRules = ''
    iifname "${config.services.tailscale.interfaceName}" oifname "${config.local.lan.interface}" accept comment "exit node traffic from tailnet to LAN"
  '';
}
