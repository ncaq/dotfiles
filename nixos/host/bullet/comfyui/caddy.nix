# `https://comfy-ui.localhost.ncaq.net`でComfyUIにアクセスできるようにするリバースプロキシ。
# DNSはCloudflare側でループバックアドレスを返すため、
# アクセスは自マシンのループバック内で完結する。
# 証明書はacmeとDNS-01により取得したLet's Encrypt証明書を使う。
# ローカルホストにのみbindして外部公開はしない。
{ config, ... }:
let
  port = config.containers.comfyui.config.services.comfyui.port;
in
{
  services.caddy = {
    enable = true;
    virtualHosts."comfy-ui.localhost.ncaq.net" = {
      useACMEHost = "comfy-ui.localhost.ncaq.net";
      extraConfig = ''
        # `bind localhost`だとCaddyは127.0.0.1にしかbindしない一方、
        # DNSはAAAAレコードの::1を返すため接続できなくなる。
        # 両方のループバックアドレスに明示的にbindする。
        bind 127.0.0.1 ::1
        reverse_proxy http://localhost:${toString port}
      '';
    };
  };
}
