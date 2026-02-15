# mcp-nixosをHTTPエンドポイントで提供します。
# リソース読み込みをするだけのMCPサーバなので認証情報は不要です。
# 万が一の危険を減らすために仮想マシンで隔離しています。
{
  pkgs,
  config,
  inputs,
  ...
}:
let
  addr = config.machineAddresses.mcp-nixos;
  # Pythonの依存関係とパッケージ自体をまとめて環境にします。
  mcp-nixos-env = pkgs.python3.withPackages (
    _: pkgs.mcp-nixos.propagatedBuildInputs ++ [ pkgs.mcp-nixos ]
  );
  # HTTPで提供するためにmcp-nixosをコマンドラインで動かすのではなくPythonモジュールを呼び出します。
  serverPy = "${pkgs.mcp-nixos}/${pkgs.python3.sitePackages}/mcp_nixos/server.py";
in
{
  imports = [
    inputs.microvm.nixosModules.host
  ];

  # 仮に脆弱性があった場合の被害を最小限に抑えるため、
  # 仮想マシンで動かします。
  microvm.vms.mcp-nixos = {
    inherit pkgs;
    config = {
      system.stateVersion = "25.11";

      microvm = {
        hypervisor = "cloud-hypervisor";
        vcpu = 1;
        mem = 512;

        interfaces = [
          {
            type = "tap";
            id = "vm-mcp-nixos";
            mac = "02:00:00:00:00:30";
          }
        ];

        # ディスクの書き込みは提供しませんが、
        # Nixのストアはキャッシュとして利用したいので読み取り専用でマウントします。
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
        interfaces.eth0.ipv4.addresses = [
          {
            address = addr.guest;
            prefixLength = 24;
          }
        ];
        defaultGateway = {
          address = addr.host;
          interface = "eth0";
        };
        firewall.allowedTCPPorts = [ 8080 ]; # Cloudflare Tunnelから転送されるポートです。
      };

      systemd.services.mcp-nixos-http = {
        description = "mcp-nixos HTTP server";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          # オリジナルのmcp-nixosはHTTPサーバでは動きませんが、
          # オリジナルでも使っているfastmcpを使うことでHTTPサーバとして動かせるようになります。
          ExecStart = "${mcp-nixos-env}/bin/fastmcp run ${serverPy}:mcp --transport streamable-http --host 0.0.0.0 --port 8080";
          DynamicUser = true;
          Restart = "always";
          RestartSec = 5;
        };
      };
    };
  };

  networking.interfaces.vm-mcp-nixos.ipv4.addresses = [
    {
      address = addr.host;
      prefixLength = 24;
    }
  ];

  # DoS攻撃に加担しないように、
  # 一応帯域制限をかけておきます。
  systemd.services.mcp-nixos-traffic-control = {
    description = "Traffic control for mcp-nixos microVM";
    requires = [ "microvm-tap-interfaces@mcp-nixos.service" ];
    after = [ "microvm-tap-interfaces@mcp-nixos.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.iproute2}/bin/tc qdisc add dev vm-mcp-nixos root tbf rate 100mbit burst 10mbit latency 400ms";
    };
  };
}
