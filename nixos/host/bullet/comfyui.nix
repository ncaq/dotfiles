{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  # ComfyUIがlistenするポート。
  # ホスト側では`comfyui-proxy.socket`が同じ番号でlistenし、
  # コンテナ内のComfyUIへ転送する。
  port = 8188;
  # コンテナのvethアドレス。
  # LANの192.168.10.0/24と重複しない範囲を使う。
  hostAddress = "192.168.100.10";
  localAddress = "192.168.100.11";
  # コンテナ内のcomfyuiユーザのID。
  # ephemeralコンテナでは動的割り当ての記録が起動ごとに消えるため、
  # bind mountした`/var/lib/comfyui`の所有権がずれないように固定する。
  # nixpkgsが静的IDに予約している400未満と、
  # 動的割り当てが使う999からの降順領域を避けた任意の値。
  comfyuiUid = 500;
  comfyuiGid = 500;
  # CUDAに必要なNVIDIAデバイスノード。
  nvidiaDevices = [
    "/dev/nvidia-modeset"
    "/dev/nvidia-uvm"
    "/dev/nvidia-uvm-tools"
    "/dev/nvidia0"
    "/dev/nvidiactl"
  ];
in
{
  # コンテナ内と同じIDでホスト側にもユーザとグループを作る。
  # bind mountした`/var/lib/comfyui`の所有者をホストからも名前で扱えるようにするため。
  users = {
    users.comfyui = {
      uid = comfyuiUid;
      group = "comfyui";
      isSystemUser = true;
    };
    groups.comfyui.gid = comfyuiGid;
  };
  # 外部から取得したモデルやカスタムノードを実行するサービスなので、
  # NixOS Containersに包んで隔離してリスクを減らす。
  containers.comfyui = {
    # ソケットアクティベーションでオンデマンド起動するのでブート時には起動しない。
    autoStart = false;
    ephemeral = true;
    privateNetwork = true;
    privateUsers = "identity";
    inherit hostAddress localAddress;
    # CUDAを使うためにNVIDIAデバイスをコンテナへ渡す。
    allowedDevices = map (node: {
      inherit node;
      modifier = "rw";
    }) nvidiaDevices;
    bindMounts =
      lib.genAttrs nvidiaDevices (device: {
        hostPath = device;
        isReadOnly = false;
      })
      // {
        # ドライバのユーザランドライブラリはホストのものを使う。
        # コンテナ内で用意するとホストのカーネルモジュールとバージョンがずれるため。
        "/run/opengl-driver" = {
          hostPath = "/run/opengl-driver";
          isReadOnly = true;
        };
        # モデルやカスタムノードなどのデータはホスト側に永続化する。
        "/var/lib/comfyui" = {
          hostPath = "/var/lib/comfyui";
          isReadOnly = false;
        };
      };
    config =
      { lib, ... }:
      {
        imports = [ inputs.comfyui-nix.nixosModules.default ];
        system.stateVersion = "26.05";
        networking.useHostResolvConf = lib.mkForce false;
        services.resolved.enable = true;
        users = {
          users.comfyui.uid = comfyuiUid;
          groups.comfyui.gid = comfyuiGid;
        };
        services.comfyui = {
          enable = true;
          gpuSupport = "cuda";
          enableManager = true;
          inherit port;
          # ホストからvethを通してアクセスするので全インターフェースでlistenする。
          # privateNetworkなのでLANには露出しない。
          listenAddress = "0.0.0.0";
          dataDir = "/var/lib/comfyui";
          # コンテナ内のfirewallを開ける。到達できるのはvethを持つホストのみ。
          openFirewall = true;
        };
      };
  };
  # ComfyUIはCUDA初期化時にnvidia-uvmを必要とするが、
  # コンテナ内からホストのカーネルモジュールはロードできないため、
  # ブート時にロードしてデバイスノードの存在を保証する。
  boot.kernelModules = [ "nvidia_uvm" ];
  networking = {
    # コンテナから外(モデルやカスタムノードのダウンロードなど)へ出られるようにする。
    nat = {
      enable = true;
      internalInterfaces = [ "ve-+" ];
    };
    # NetworkManagerがコンテナのvethを管理しようとして競合するのを防ぐ。
    networkmanager.unmanaged = [ "interface-name:ve-*" ];
  };
  # GPUを触るサービスを常時起動させたくないので、
  # ソケットアクティベーションによるオンデマンド起動にする。
  # `comfyui-proxy.socket`がホスト側でlistenし、
  # 初回アクセス時にsystemd-socket-proxyd経由でコンテナごと起動する。
  # アイドル時の自動停止は誤爆が怖いので設定しない。
  # 停止したい時は手動で`systemctl stop container@comfyui.service`する。
  systemd = {
    services = {
      comfyui-proxy = {
        description = "systemd-socket-proxyd for on-demand ComfyUI activation";
        requires = [ "container@comfyui.service" ];
        after = [ "container@comfyui.service" ];
        serviceConfig = {
          # systemd-socket-proxydは`bin/`ではなく`lib/systemd/`に配置されるため、
          # `lib.getExe'`は使えない。
          ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd ${localAddress}:${toString port}";
          DynamicUser = true;
          PrivateTmp = true;
        };
      };
      "container@comfyui" = {
        # コンテナが起動してもComfyUIがlistenするまでは時間がかかり、
        # その前にproxydが接続すると初回リクエストが失敗してしまう。
        # HTTP疎通を確認してから起動完了扱いにする。
        postStart = ''
          until ${lib.getExe pkgs.curl} --fail --silent --output /dev/null "http://${localAddress}:${toString port}/"; do
            ${pkgs.coreutils}/bin/sleep 1
          done
        '';
      };
    };
    sockets.comfyui-proxy = {
      description = "Socket for on-demand ComfyUI activation";
      listenStreams = [
        "127.0.0.1:${toString port}"
        "[::1]:${toString port}"
      ];
      wantedBy = [ "sockets.target" ];
    };
  };
  # `https://comfy-ui.localhost.ncaq.net`でComfyUIにアクセスできるようにするリバースプロキシ。
  # DNSはCloudflare側でループバックアドレスを返すため、
  # アクセスは自マシンのループバック内で完結する。
  # 証明書はacmeとDNS-01により取得したLet's Encrypt証明書を使う。
  # ローカルホストにのみbindして外部公開はしない。
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
