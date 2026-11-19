/**
  名前解決に使う公開DNSサーバの一覧を、アドレスファミリごとに分けたもの。

  型: { ipv6 :: [{ address :: String; name :: String; }]; ipv4 :: [{ address :: String; name :: String; }]; }

  以下が同じ一覧を使う。

  - ホストのsystemd-resolved(`nixos/native-linux/networking.nix`)
  - コンテナのsystemd-resolvedのフォールバック(同じファイルで全コンテナへ入れる)
  - microVMのsystemd-networkd(`lib/microvm-tap.nix`)

  それぞれに書くと、
  サーバを入れ替えた時や並び順を変えた時に片方だけが古いまま残る。

  使う側は`ipv6`を先に、`ipv4`を後ろに並べる。
  systemd-resolvedは先頭のサーバを使い、応答しなくなった時に次へ移るので、
  並び順がそのまま優先順位になる。
  IPv4のサーバはIPv6で届かない時の予備にする。
  IPv4を持たないマシンには`ipv4`を渡さない。
  アドレスファミリごとにフィールドを分けているのは、
  使う側がアドレスの文字列からアドレスファミリを推測せずに済むようにするため。

  CloudflareのDNSリゾルバが稀に不調になることがあるためGoogleでも解決できるように、
  両者を混在させる。

  `name`はDNS over TLSでサーバの証明書を確かめる名前。
  systemd-resolvedには`"<address>#<name>"`の形で渡す。

  tailnetの端末が使うDNSサーバは、
  infra.ncaq.netの`tailscale/dns.tf`に同じ方針で別に書いている。
*/
{
  ipv6 = [
    # Cloudflare
    {
      address = "2606:4700:4700::1111";
      name = "one.one.one.one";
    }
    {
      address = "2606:4700:4700::1001";
      name = "one.one.one.one";
    }
    # Google
    {
      address = "2001:4860:4860::8888";
      name = "dns.google";
    }
    {
      address = "2001:4860:4860::8844";
      name = "dns.google";
    }
  ];
  ipv4 = [
    # Cloudflare
    {
      address = "1.1.1.1";
      name = "one.one.one.one";
    }
    {
      address = "1.0.0.1";
      name = "one.one.one.one";
    }
    # Google
    {
      address = "8.8.8.8";
      name = "dns.google";
    }
    {
      address = "8.8.4.4";
      name = "dns.google";
    }
  ];
}
