{ lib, config, ... }:
let
  garageAddr = config.machineAddresses.garage.guest6;
  garageHostAddr = config.machineAddresses.garage.host6;
  niks3PublicHostAddr = config.machineAddresses.niks3-public.host6;
  niks3PrivateHostAddr = config.machineAddresses.niks3-private.host6;
  containerIfname = name: import ../../../lib/container-ifname.nix { inherit lib name; };
in
{
  # ホスト上でgarage.ncaq.netをローカルのCaddyへ向けます。
  # garage.ncaq.netはniks3が発行するpresigned URLのアップロード先なので、
  # ホストからniks3-privateへのキャッシュのアップロードがマシン内で完結します。
  # 向き先は用途に対応するvethのホスト側アドレスにして、
  # 障害の切り分けが素直になるようにします。
  #
  # niks3-public.ncaq.netはここへ向けません。
  # 以前はCIランナーがホストのnix-daemonを使っていたので、
  # ホストで名前を内部へ向ければCIのキャッシュの出し入れがマシン内で完結しました。
  # 今のランナーはmicroVMの中のnix-daemonを使い、公開DNSで引いてCloudflare Tunnel経由で届きます。
  # ホスト自身はniks3-privateを優先して使うので、内部の経路を持つ意味が無くなりました。
  #
  # ここに書いた名前は、seminarをexit nodeにしている端末にも内部アドレスとして見えます。
  # exit nodeを使う端末は全てのDNSクエリをexit node側のtailscaledへ送り、
  # exit node側のtailscaledは`/etc/resolv.conf`の先頭のnameserverへ問い合わせます。
  # seminarではそれがsystemd-resolvedのstubで、
  # systemd-resolvedは`/etc/hosts`の内容も答えに使うためです。
  # その端末が内部アドレスへ辿り着けるようにする経路広告は`tailscale-exit-node.nix`にあり、
  # このオプションのアドレスをそのまま広告します。
  # `networking.hosts`に直接書かずオプションにしているのは、
  # 名前の向き先と経路広告を手で揃える必要を無くすためです。
  # 片方だけ変えると名前は引けるのに経路が無い状態になり、
  # エラーも出ずに繋がらなくなります。
  #
  # ただしinfra.ncaq.net側の経路の承認とACLまでは追従しません。
  # ここへ名前を足す時は、Caddyがその名前のvhostを受けることと、
  # infra.ncaq.netの`tailscale/subnet-route.tf`と`tailscale/access-policy.tf`に、
  # 同じアドレスを足すことの両方が要ります。
  options.local.caddyInternalHosts = lib.mkOption {
    type = lib.types.attrsOf (lib.types.listOf lib.types.str);
    readOnly = true;
    default = {
      ${garageHostAddr} = [ "garage.ncaq.net" ];
    };
    description = ''
      ホスト上のCaddyへ向ける名前の、vethのホスト側アドレスから名前のリストへの対応。
      `networking.hosts`と`tailscale-exit-node.nix`の経路広告の両方がここから組み立てる。
    '';
  };

  config = {
    services.caddy = {
      enable = true;
      email = "ncaq@ncaq.net";
      # niks3コンテナとホスト自身からGarageへのTLS termination proxy。
      # 同じサーバ上の通信なのにいちいちCloudflare Tunnelを経由すると無駄なので、
      # ローカルのCaddyで通信を橋渡しします。
      # niks3コンテナ内のhostsとホストのnetworking.hostsでgarage.ncaq.netをここへ向け、
      # Caddy(Let's Encrypt証明書)経由でGarageに直接HTTP接続することでバイパスします。
      # それによりpresigned URLはhttps://garage.ncaq.net/...のまま維持されます。
      # 外部クライアント(GitHub Actionsなど)はCloudflare Tunnel経由でアクセスします。
      # ホストの443を完全に占有してしまわないように、
      # garageとniks3各コンテナのvethのホスト側アドレスのみにバインドします。
      virtualHosts."garage.ncaq.net" = {
        useACMEHost = "garage.ncaq.net";
        extraConfig = ''
          bind [${garageHostAddr}] [${niks3PublicHostAddr}] [${niks3PrivateHostAddr}]
          reverse_proxy http://[${garageAddr}]:3900
        '';
      };
    };
    networking = {
      # 名前の向き先は`local.caddyInternalHosts`を参照。
      hosts = config.local.caddyInternalHosts;
      # garage.ncaq.netをホストのCaddy経由で使うniks3の2つのコンテナのvethからだけ、
      # Caddyの443への接続を許可する。
      # 他のコンテナがvethのホスト側アドレスの443へ繋ぐ用途は無い。
      # CIランナーの中のniks3クライアントも公開DNSで引いてCloudflare Tunnel経由で届く。
      # インターフェイス名は`ve-niks3-private`が15文字に収まらず縮められるので、
      # `lib/container-ifname.nix`でパターンにする。
      #
      # Tailscale経由の接続はここでは開けない。
      # tailscaledが`INPUT`の先頭に挿す`ts-input`チェインが、
      # Tailscaleインターフェースから入る全パケットを先にACCEPTするので、
      # NixOSのfirewallはそもそも評価されない。
      # exit node経由の端末からこのアドレスへ届くかどうかは、
      # tailscaledのパケットフィルタとtailnetのACLで決まる。
      # `tailscale-exit-node.nix`を参照。
      firewall.interfaces =
        lib.genAttrs
          (map containerIfname [
            "niks3-public"
            "niks3-private"
          ])
          (_: {
            allowedTCPPorts = [ 443 ];
          });
    };
    # vethインターフェースはコンテナ起動時に作成されるため、
    # Caddy起動時にはまだバインド先IPが存在しない場合がある。
    # ip_nonlocal_bindを有効にして未割当アドレスへのバインドを許可する。
    # IPv6ではアドレスが付いた直後の重複検出(DAD)が終わるまでの間も、
    # これが無いとバインドに失敗する。
    # vethのホスト側に待ち受けるアドレスはIPv6だけなので、IPv6の側だけを有効にする。
    boot.kernel.sysctl."net.ipv6.ip_nonlocal_bind" = 1;
  };
}
