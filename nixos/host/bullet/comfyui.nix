{ inputs, ... }: {
  imports = [ inputs.comfyui-nix.nixosModules.default ];
  services.comfyui = {
    enable = true;
    gpuSupport = "cuda";
    enableManager = true;
    port = 8188; # デフォルトですが競合しやすいポートという性質上明示しておきます。
    listenAddress = "localhost"; # "0.0.0.0"にすると外部からアクセス可能になります。
    dataDir = "/var/lib/comfyui";
    openFirewall = false; # デフォルトですが分かり易いように明示しておきます。
  };
  # `https://comfy-ui.localhost.ncaq.net`でComfyUIにアクセスできるようにするリバースプロキシ。
  # DNSはCloudflare側でループバックアドレスを返すため、
  # アクセスは自マシンのループバック内で完結する。
  # 証明書はcloudflare.nixでDNS-01により取得したLet's Encrypt証明書を使う。
  # ローカルホストにのみbindして外部公開はしない。
  services.caddy = {
    enable = true;
    virtualHosts."comfy-ui.localhost.ncaq.net" = {
      useACMEHost = "comfy-ui.localhost.ncaq.net";
      extraConfig = ''
        bind localhost
        reverse_proxy http://localhost:8188
      '';
    };
  };
}
