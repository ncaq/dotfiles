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
      # DHCPで配られるDNS(家庭用ルータ等のDoT非対応のもの)をsystemd-resolvedに渡さない。
      # これがないとper-link DNSとして優先されて、
      # `DNSOverTLS=true`(strict)で解決失敗します。
      connectionConfig = {
        "ipv4.ignore-auto-dns" = true;
        "ipv6.ignore-auto-dns" = true;
      };
    };
    nameservers = encryptedDns;
  };

  services.resolved = {
    enable = true;
    dnssec = "true";
    # Tailscaleが有効な環境ではDNSクエリはTailscaleの内部DNSサーバに流れます。
    # Tailscale側は同じくCloudflareかGoogleのDNSを使うように設定しています。
    # その時にDNS over HTTPSが利用されます。
    # しかし念の為Tailscaleが外れた時も比較的安全にDNSが解決できるように、
    # 本体の設定でもDNS over TLSを利用するようにします。
    dnsovertls = "true";
    fallbackDns = encryptedDns;
  };
}
