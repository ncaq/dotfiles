# ComfyUI本体を隔離して動かすNixOS Containersの定義。
{
  lib,
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
  dataDir = "/var/lib/comfyui";
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
        ${dataDir} = {
          hostPath = dataDir;
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
          inherit dataDir;
          # コンテナ内のfirewallを開ける。到達できるのはvethを持つホストのみ。
          openFirewall = true;
          # xformers 0.0.30のflash-attentionカーネルはBlackwell(sm_120)のカーネルイメージを含まず、
          # Qwen系モデルのサンプリング開始時に、
          # `CUDA error: no kernel image is available for execution on the device`
          # でクラッシュするためPyTorch組み込みのSDPAを使う。
          extraArgs = [ "--use-pytorch-cross-attention" ];
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
  # bind mountするデータディレクトリをホスト側で用意する。
  systemd.tmpfiles.rules = [ "d ${dataDir} 0750 comfyui comfyui - -" ];
}
