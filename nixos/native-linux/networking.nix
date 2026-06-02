_:
let
  # DNS over TLSが利用できるPublic DNSサーバーのリスト。
  # CloudflareのDNSリゾルバが稀に不調になることがあるためGoogleでも解決できるように、
  # 両者を混在させます。
  encryptedDns = [
    # Cloudflare
    # IPv4
    "1.1.1.1#one.one.one.one"
    "1.0.0.1#one.one.one.one"
    # IPv6
    "2606:4700:4700::1111#one.one.one.one"
    "2606:4700:4700::1001#one.one.one.one"
    # Google
    # IPv4
    "8.8.8.8#dns.google"
    "8.8.4.4#dns.google"
    # IPv6
    "2001:4860:4860::8888#dns.google"
    "2001:4860:4860::8844#dns.google"
  ];
in
{
  networking = {
    networkmanager = {
      enable = true;
      # NMが「Wired connection 1」のような一時プロファイル(nm-generated=true)を、
      # 明示プロファイルのない管理対象NICに自動生成するのを抑止する。
      # 宣言的に書いたプロファイル以外がランタイムに出現するのを防ぐ。
      settings.main.no-auto-default = "*";
    };
    nameservers = encryptedDns;
  };

  programs = {
    nm-applet = {
      enable = true;
    };
  };

  services.resolved = {
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
      };
    };
  };
}
