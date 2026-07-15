{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  # 外部(Caddyやブラウザ)から見えるポート。comfyui-proxy.socketがlistenする。
  proxyPort = 8188;
  # ComfyUI本体が実際にlistenするポート。systemd-socket-proxydからのみ使う。
  comfyuiPort = 8189;
in
{
  imports = [ inputs.comfyui-nix.nixosModules.default ];
  services = {
    comfyui = {
      enable = true;
      gpuSupport = "cuda";
      enableManager = true;
      port = comfyuiPort;
      # proxydの転送先やpostStartの疎通確認と一致させるため、
      # localhostではなく127.0.0.1で明示的にbindする。
      listenAddress = "127.0.0.1";
      dataDir = "/var/lib/comfyui";
      openFirewall = false; # デフォルトですが分かり易いように明示しておきます。
    };
    # `https://comfy-ui.localhost.ncaq.net`でComfyUIにアクセスできるようにするリバースプロキシ。
    # DNSはCloudflare側でループバックアドレスを返すため、
    # アクセスは自マシンのループバック内で完結する。
    # 証明書はcloudflare.nixでDNS-01により取得したLet's Encrypt証明書を使う。
    # ローカルホストにのみbindして外部公開はしない。
    caddy = {
      enable = true;
      virtualHosts."comfy-ui.localhost.ncaq.net" = {
        useACMEHost = "comfy-ui.localhost.ncaq.net";
        extraConfig = ''
          # `bind localhost`だとCaddyは127.0.0.1にしかbindしない一方、
          # DNSはAAAAレコードの::1を返すため接続できなくなる。
          # 両方のループバックアドレスに明示的にbindする。
          bind 127.0.0.1 ::1
          reverse_proxy http://localhost:${toString proxyPort}
        '';
      };
    };
  };
  # GPUを触るサービスを毎回常時起動させたくないので、
  # ソケットアクティベーションによるオンデマンド起動にする。
  # `comfyui-proxy.socket`が従来のポートをlistenし、
  # 初回アクセス時にsystemd-socket-proxyd経由でComfyUI本体を起動する。
  # アイドル時の自動停止は誤爆が怖いので設定しない。
  # 停止したい時は手動で`systemctl stop comfyui.service`する。
  systemd = {
    services = {
      comfyui-proxy = {
        description = "systemd-socket-proxyd for on-demand ComfyUI activation";
        requires = [ "comfyui.service" ];
        after = [ "comfyui.service" ];
        serviceConfig = {
          ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:${toString comfyuiPort}";
          DynamicUser = true;
          PrivateTmp = true;
        };
      };
      comfyui = {
        # ブート時には起動せず、ソケットへの初回アクセスで起動させる。
        wantedBy = lib.mkForce [ ];
        # Type=simpleなのでexecした時点で起動完了扱いになり、
        # 実際にlistenする前にproxydが接続して初回リクエストが失敗してしまう。
        # listen開始を確認してから起動完了扱いにする。
        postStart = ''
          until ${lib.getExe pkgs.curl} --fail --silent --output /dev/null "http://127.0.0.1:${toString comfyuiPort}/"; do
            ${pkgs.coreutils}/bin/sleep 1
          done
        '';
        # PyTorchとCUDAの初期化で起動に時間がかかることがあるので余裕を持たせる。
        serviceConfig.TimeoutStartSec = "5min";
      };
    };
    sockets.comfyui-proxy = {
      description = "Socket for on-demand ComfyUI activation";
      listenStreams = [
        "127.0.0.1:${toString proxyPort}"
        "[::1]:${toString proxyPort}"
      ];
      wantedBy = [ "sockets.target" ];
    };
  };
}
