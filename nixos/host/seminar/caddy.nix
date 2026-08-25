{ config, ... }:
let
  garageAddr = config.machineAddresses.garage.guest;
  niks3PublicAddr = config.machineAddresses.niks3-public.guest;
  niks3PublicHostAddr = config.machineAddresses.niks3-public.host;
  niks3PrivateAddr = config.machineAddresses.niks3-private.guest;
  niks3PrivateHostAddr = config.machineAddresses.niks3-private.host;
in
{
  services.caddy = {
    enable = true;
    email = "ncaq@ncaq.net";
    # niks3コンテナからGarageへのTLS termination proxy。
    # 同じサーバ上の通信なのにいちいちCloudflare Tunnelを経由すると無駄なので、
    # ローカルのCaddyで通信を橋渡しします。
    # コンテナ内のhostsでgarage.ncaq.netをhostAddressに向け、
    # Caddy(Let's Encrypt証明書)経由でGarageに直接HTTP接続することでバイパスします。
    # それによりpresigned URLはhttps://garage.ncaq.net/...のまま維持されます。
    # 外部クライアント(GitHub Actionsなど)はCloudflare Tunnel経由でアクセスします。
    # ホストの443を完全に占有してしまわないように、
    # niks3コンテナのhostAddress側vethのみにバインドします。
    virtualHosts."garage.ncaq.net" = {
      useACMEHost = "garage.ncaq.net";
      extraConfig = ''
        bind ${niks3PublicHostAddr} ${niks3PrivateHostAddr}
        reverse_proxy http://${garageAddr}:3900
      '';
    };
    # ホスト自身からniks3-publicへのアクセスをマシン内で完結させるproxy。
    # niks3-public.ncaq.netの公開経路はCloudflare Tunnelのみなので、
    # そのままだと同じマシン上のキャッシュへCloudflareを往復して到達することになります。
    # substituteやpost-build-hookはホストのnix-daemonが実行するため、
    # ホストのnetworking.hostsで名前をこのバインド先へ向けることで、
    # CIランナーのキャッシュ入出力もマシン内で完結します。
    # https://github.com/ncaq/dotfiles/issues/1535
    virtualHosts."niks3-public.ncaq.net" = {
      useACMEHost = "niks3-public.ncaq.net";
      extraConfig = ''
        bind ${niks3PublicHostAddr}
        reverse_proxy http://${niks3PublicAddr}:5751
      '';
    };
    # Tailscale Serve(tailnet専用)からのリクエストを受けるリバースプロキシ。
    # Tailscale ServeがTLS終端し、ここにHTTPで転送する。
    # Caddy v2では`localhost`はlocal CAによる自動HTTPSの対象になるため、
    # `localhost:8081`だとHTTPSが有効化され、Tailscale ServeからのHTTPプロキシが失敗する。
    # `:8081`(ホスト名なし)にしてbind 127.0.0.1でHTTPのみに限定する。
    virtualHosts.":8081".extraConfig = ''
      bind 127.0.0.1
      handle_path /niks3/private/* {
        reverse_proxy http://${niks3PrivateAddr}:5751
      }
      redir /niks3/private /niks3/private/
    '';
  };
  networking = {
    # ホスト上でniks3-public.ncaq.netとgarage.ncaq.netをローカルのCaddyへ向けます。
    # substituteはホストのnix-daemonが行うため、
    # これによりCIのキャッシュ取得がCloudflare Tunnelを経由しなくなります。
    # garage.ncaq.netはniks3が発行するpresigned URLのアップロード先なので、
    # キャッシュへのアップロードもマシン内で完結します。
    hosts.${niks3PublicHostAddr} = [
      "niks3-public.ncaq.net"
      "garage.ncaq.net"
    ];
    # コンテナのvethインターフェースからCaddyの443への接続を許可する。
    firewall.interfaces."ve-+".allowedTCPPorts = [ 443 ];
  };
  # vethインターフェースはコンテナ起動時に作成されるため、
  # Caddy起動時にはまだバインド先IPが存在しない場合がある。
  # ip_nonlocal_bindを有効にして未割当アドレスへのバインドを許可する。
  boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = 1;
}
