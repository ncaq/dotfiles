{ lib, ... }:
let
  publicDns = import ../../lib/public-dns.nix;
  # systemd-resolvedへ渡す、DNS over TLSで確かめる名前付きの形。
  withName = servers: map (server: "${server.address}#${server.name}") servers;
  encryptedDns = withName publicDns;
in
{
  # コンテナのsystemd-resolvedもホストと同じ公開DNSを使う。
  # コンテナはDNSサーバを教わらないので、フォールバックの一覧がそのまま使われる。
  # 何も書かないとsystemdに組み込まれた一覧になり、IPv4のサーバが先に並ぶ。
  # IPv4を持たないコンテナからはIPv4のサーバに届かないので外す。
  options.containers = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { config, ... }:
        {
          config.config.services.resolved.settings.Resolve.FallbackDNS = withName (
            lib.filter (server: config.localAddress != null || lib.hasInfix ":" server.address) publicDns
          );
        }
      )
    );
  };

  config.networking = {
    networkmanager = {
      enable = true;
      # NMが「Wired connection 1」のような一時プロファイル(nm-generated=true)を、
      # 明示プロファイルのない管理対象NICに自動生成するのを抑止する。
      # 宣言的に書いたプロファイル以外がランタイムに出現するのを防ぐ。
      settings.main.no-auto-default = "*";
    };
    # NetworkManagerが既定で有効にするが、
    # モデムを持つホストは無いので動かさない。
    modemmanager.enable = false;
    nameservers = encryptedDns;
  };

  config.programs = {
    nm-applet = {
      enable = true;
    };
  };

  config.services.resolved = {
    enable = true;
    settings = {
      Resolve = {
        DNSSEC = "true";
        # Tailscaleが有効な環境ではDNSクエリはTailscaleの内部DNSサーバに流れます。
        # Tailscale側は同じくCloudflareかGoogleのDNSを使うように設定しています。
        # その時にDNS over HTTPSが利用されます。
        # しかし念の為Tailscaleが外れた時も比較的安全にDNSが解決できるように、
        # 本体の設定でもDNS over TLSを利用するようにします。
        DNSOverTLS = "true";
        FallbackDNS = encryptedDns;
        # LLMNRはDNSで引けなかった名前をリンクローカルにマルチキャストで問い合わせて、
        # 名乗り出た相手を認証無しに信じる仕組みなので、
        # 同じLANにいる攻撃者が任意の名前を自分に向けられる(Responder系の攻撃)。
        # ホストの探索はwsddとavahi(mDNS)で足りているので、問い合わせる側としても無効にする。
        LLMNR = "false";
      };
    };
  };
}
