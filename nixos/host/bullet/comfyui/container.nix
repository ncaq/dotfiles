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
  # idmap付きbind mountは数値IDをホストとコンテナで同一視するため、
  # `privateUsers = "pick"`でもこの固定が引き続き必要。
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
    # 毎起動ランダムな高位UID範囲へマップして、
    # コンテナを脱出されてもホスト上では無権限のUIDになるようにする。
    # identityと違いコンテナ内rootがホストのUID 0を持たなくなる。
    privateUsers = "pick";
    inherit hostAddress localAddress;
    # CUDAを使うためにNVIDIAデバイスをコンテナへ渡す。
    allowedDevices = map (node: {
      inherit node;
      modifier = "rw";
    }) nvidiaDevices;
    # NVIDIAデバイスノードは0666、ドライバライブラリはworld-readableなので、
    # UIDがマップされないpickでもotherパーミッションでアクセスできる。
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
      };
    # モデルやカスタムノードなどのデータはホスト側に永続化する。
    # pickでは素のbind mountだと所有者が無効なUIDに見えて書き込めないため、
    # idmapオプションで数値IDをホストとコンテナで同一視させる。
    # `bindMounts`はマウントオプションを渡せないのでextraFlagsで指定する。
    extraFlags = [ "--bind=${dataDir}:${dataDir}:idmap" ];
    config =
      {
        lib,
        pkgs,
        config,
        ...
      }:
      let
        comfyuiPython = config.services.comfyui.package.pythonRuntime.python;
        # python.pkgs.torchはoverride前なので、実行環境に含まれるCUDA wheel版を使う。
        torch = lib.findFirst (
          pkg: lib.getName pkg == "torch"
        ) (throw "torch not found in comfyui heavyDeps") config.services.comfyui.package.heavyDeps;
        inherit (torch) cudaPackages;
        cudaNvcc = cudaPackages.cuda_nvcc;
        cudaNvrtc = cudaPackages.cuda_nvrtc;
        sageattention = comfyuiPython.pkgs.callPackage ../../../../pkgs/sageattention.nix {
          inherit torch;
          # torchの全CUDA世代ではなく、RTX 5090向けのカーネルだけをビルドする。
          cudaCapabilities = [ "12.0" ];
        };
        seedvr2PythonDeps = with comfyuiPython.pkgs; [ rotary-embedding-torch ];
        loraManagerPythonEnv = comfyuiPython.withPackages (
          pythonPkgs: with pythonPkgs; [
            aiohttp
            aiohttp-socks
            aiosqlite
            beautifulsoup4
            brotli
            gitpython
            jinja2
            natsort
            numpy
            olefile
            piexif
            pillow
            platformdirs
            pyyaml
            safetensors
            toml
          ]
        );
      in
      {
        imports = [ inputs.utensils-comfyui-nix.nixosModules.default ];
        system.stateVersion = "26.05";
        # コンテナにはホストのタイムゾーンが伝播しないため明示する。
        # 未設定だとUTCになり、出力ファイル名の生成日時がJSTとずれる。
        time.timeZone = "Asia/Tokyo";
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
          extraArgs = [
            # WanのRoPEやFP8量子化処理をeager実装からTritonカーネルへ切り替える。
            "--enable-triton-backend"
            # FP16の行列積で低精度の累積を許可して、LoRAやFP16 fallbackを高速化する。
            # 丸め誤差が増えるため生成結果は変化する可能性がある。
            "--fast"
            "fp16_accumulation"
            # xformers 0.0.30はBlackwell(sm_120)に対応していないため使わない。
            # SageAttentionで動画生成の大半を占めるattentionを近似計算して高速化する。
            "--use-sage-attention"
          ];
        };
        # Tritonは未指定時にNixOSには存在しない`/sbin/ldconfig`でlibcudaを探す。
        systemd.services.comfyui.environment = {
          CC = lib.getExe pkgs.stdenv.cc;
          # SeedVR2のVAE attentionが実行時コンパイルにNVRTCを使う。
          # ComfyUIのtorchと同じCUDAパッケージセットから検索パスを指定する。
          LD_LIBRARY_PATH = lib.makeLibraryPath [ cudaNvrtc ];
          PYTHONPATH = lib.makeSearchPath comfyuiPython.sitePackages (
            [
              sageattention
              loraManagerPythonEnv
            ]
            ++ seedvr2PythonDeps
          );
          TRITON_CUDACRT_PATH = "${cudaPackages.cuda_cudart}/include";
          TRITON_LIBCUDA_PATH = "/run/opengl-driver/lib";
          TRITON_LIBDEVICE_PATH = "${cudaNvcc}/nvvm/libdevice/libdevice.10.bc";
          TRITON_PTXAS_PATH = "${cudaNvcc}/bin/ptxas";
        };
        systemd.services.comfyui.path = with pkgs; [ ffmpeg ];
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
