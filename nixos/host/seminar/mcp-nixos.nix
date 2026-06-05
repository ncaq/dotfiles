/**
  mcp-nixosをHTTPエンドポイントで提供します。
  以下のURLで提供しているので、
  MCPクライアントには以下のURLを入力してください。
  `https://mcp-nixos.ncaq.net/mcp`
  読み取り専用のMCPサーバなので認証情報は不要です。
  万が一の危険を減らすために仮想マシンで隔離しています。
*/
{
  pkgs,
  config,
  ...
}:
let
  addr = config.machineAddresses.mcp-nixos;
in
{
  # 仮に脆弱性があった場合の被害を最小限に抑えるため仮想マシンで動かします。
  microvm.vms.mcp-nixos = {
    inherit pkgs;
    config = {
      system.stateVersion = "26.05";
      microvm = {
        hypervisor = "cloud-hypervisor";
        vsock.cid = config.microvmCid.mcp-nixos;
        vcpu = 1;
        # 実測ピークが約494MiB(NixOS基盤 + Python + mcp-nixos込み)なので、
        # 約30%の余裕を持って640MiBにしています。
        mem = 640;
        interfaces = [
          {
            type = "tap";
            id = "vm-mcp-nixos";
            mac = "02:00:00:00:00:31"; # 末尾バイトはゲストIPアドレスに対応
          }
        ];
        # ディスクの書き込みは提供しませんが、
        # Nixのストアは実行ファイルやキャッシュを利用したいので読み取り専用でマウントします。
        shares = [
          {
            tag = "ro-store";
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
            proto = "virtiofs";
          }
        ];
      };
      networking = {
        hostName = "mcp-nixos";
        firewall.allowedTCPPorts = [ 8080 ]; # Cloudflare Tunnelから転送されるポートです。
      };
      systemd = {
        network = {
          enable = true;
          networks."20-lan" = {
            matchConfig.Type = "ether";
            networkConfig = {
              Address = "${addr.guest}/24";
              Gateway = addr.host;
              DNS = [
                "1.1.1.1"
                "1.0.0.1"
                "8.8.8.8"
                "8.8.4.4"
              ];
            };
          };
        };
        services.mcp-nixos-http = {
          description = "mcp-nixos HTTP server";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            # mcp-nixosはHTTPトランスポートをネイティブにサポートしているので、
            # 環境変数で設定して直接起動します。
            # パスは未指定だとデフォルトの`/mcp`になり、Cloudflare Tunnelの転送先と一致します。
            Environment = [
              "MCP_NIXOS_TRANSPORT=http"
              "MCP_NIXOS_HOST=0.0.0.0"
              "MCP_NIXOS_PORT=8080"
            ];
            ExecStart = "${pkgs.mcp-nixos}/bin/mcp-nixos";
            DynamicUser = true;
            Restart = "always";
            RestartSec = 5;
            # Hardening
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            PrivateDevices = true;
          };
        };
      };
    };
  };
  systemd = {
    network = {
      enable = true;
      # microvm.nixの推奨に従いsystemd-networkdでTAPインターフェースを設定します。
      # networking.interfacesが生成するnetwork-addresses-*サービスは、
      # network.targetより前に順序付けられるため、
      # network.targetより後に作成されるTAPインターフェースと相性が悪いです。
      networks."20-vm-mcp-nixos" = {
        matchConfig.Name = "vm-mcp-nixos";
        addresses = [
          { Address = "${addr.host}/32"; }
        ];
        routes = [
          { Destination = "${addr.guest}/32"; }
        ];
      };
    };
    # DoS攻撃に加担しないように、
    # 一応帯域制限をかけておきます。
    services.mcp-nixos-traffic-control = {
      description = "Traffic control for mcp-nixos microVM";
      requires = [ "microvm-tap-interfaces@mcp-nixos.service" ];
      after = [ "microvm-tap-interfaces@mcp-nixos.service" ];
      bindsTo = [ "microvm-tap-interfaces@mcp-nixos.service" ];
      wantedBy = [ "microvm-tap-interfaces@mcp-nixos.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart =
          "${pkgs.iproute2}/bin/tc qdisc replace dev vm-mcp-nixos root tbf"
          + " rate 100mbit burst 10mbit latency 400ms";
      };
    };
  };
}
