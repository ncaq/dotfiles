# ComfyUI本体を隔離して動かすNixOS Containersの定義。
{
  lib,
  config,
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
        ...
      }:
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
            # モデルの重みをpinned memoryへコピーせず、
            # mmapしたディスク上の重みからGPUへ転送する。
            #
            # ComfyUIはpinned memoryの上限を、
            # `max(ram * 0.40, min(ram * 0.90, ram - 4GiB, ram + ディスクswap - 16GiB))`
            # で決める。
            # この計算はzramを意図的にディスクswapから除外する。
            # pinned memoryはカーネルが回収もswap outもできないので、
            # ホストの他のプロセスやページキャッシュの分が残らない。
            #
            # 実際にanime-videoでOOM killerが発動した。
            # Wan 2.2のhigh/lowが27GiBずつとumt5_xxl_fp16の11GiBで、
            # プロセスのanon-rssは65.0GiBに達していた。
            # cgroupの`MemoryMax`(84.3GiB)には届いていないためそちらでは止まらず、
            # 回収できないinactive_anonを47GiB抱えたままglobal OOMになった。
            #
            # このフラグを付けるとdynamic VRAMのsignatureを持つ層で、
            # `pin_memory`を呼ばずにmmapから直接転送する経路を通るため、
            # 重みのRAM常駐が消える。
            # dynamic VRAMはNVIDIAかつtorch 2.8以上かつ非WSLで自動的に有効になり、
            # このホストは条件を満たす。
            # 重みの供給がディスク速度に律速するようになるが、
            # モデルはNVMe(SN8100)上のNix storeにあるので許容できる。
            "--fast-disk"
            # WanのRoPEやFP8量子化処理をeager実装からTritonカーネルへ切り替える。
            "--enable-triton-backend"
            "--fast"
            # FP16の行列積で低精度の累積を許可して、LoRAやFP16 fallbackを高速化する。
            # 丸め誤差が増えるため生成結果は変化する可能性がある。
            "fp16_accumulation"
            # 重みがfp8_e4m3fnの層の行列積をTensor Coreのfp8演算で行う。
            # 実測でbf16の0.622msに対しfp8は0.253msだった(4096角のGEMM)。
            #
            # 現在使っているモデルには効かない。
            # 量子化済みモデルは各層に`comfy_quant`マーカーを持つため、
            # `pick_operations`がこのフラグを見る前にmixed precision経路へ抜けて、
            # 層ごとの量子化設定に従うためである。
            # 効くのはマーカーを持たない素のfp8チェックポイントを足した時で、
            # その時に指定し忘れないよう先に入れておく。
            "fp8_matrix_mult"
            # xformers 0.0.30はBlackwell(sm_120)に対応していないため使わない。
            # comfy-kitchen同梱のINT8 attentionで、
            # 動画生成の大半を占めるattentionを近似計算して高速化する。
            #
            # 自前ビルドのSageAttention 2.2.0から乗り換えた。
            # (h=40, s=32760, d=128)のマイクロベンチではRTX 5090上で、
            # PyTorch SDPAの99.12msに対しSageAttentionが37.65ms、こちらが39.75msで、
            # ガウス乱数入力の相対誤差は前者0.0385に対しこちらが0.0160だった。
            # 5%の速度差と引き換えにCUDAソースビルドを1つ丸ごと減らせる。
            #
            # 利用不可ならComfyUIは黙って別実装へ落ちずに起動時点で終了するので、
            # 気付かないまま遅い実装で動き続けることはない。
            "--use-ck-attention"
          ];
        };
        systemd.services.comfyui.path = with pkgs; [
          ffmpeg
          oxipng
        ];
      };
  };
  networking = {
    # コンテナから外(モデルやカスタムノードのダウンロードなど)へ出られるようにする。
    nat = {
      enable = true;
      internalInterfaces = [ "ve-+" ];
    };
    # NetworkManagerがコンテナのvethを管理しようとして競合するのを防ぐ。
    networkmanager.unmanaged = [ "interface-name:ve-*" ];
  };
  systemd = {
    services."container@comfyui".serviceConfig = {
      # OSや他の処理のために2スレッド分を残す既存のCPU予算を使う。
      CPUQuota = "${toString (config.local.cpuBudgetThreads * 100)}%";
      # VRAMだけでなくシステムRAMも大量に使うことがあり、
      # モデルのロードやオフロードの挙動次第でホスト全体が応答しなくなるため上限を設ける。
      #
      # `--fast-disk`を付ける前は重みがpinned memoryに常駐して、
      # Wan 2.2の動画生成が実測でピーク67.9GiBを正当に必要としていた。
      # 当時`MemoryHigh`をそれより下に置くと、
      # 超過分を回収しようにも回収できるものがないため、
      # プロセスを同期回収に付き合わせ続けて生成が進まなくなった。
      # 実際に50%(46.8GiB)ではGPU使用率が0%のまま、
      # `memory.pressure`のfullが69%に達して停止していた。
      #
      # 現在はanime-videoの実測でプロセスのピークRSSが23.2GiBに収まる。
      # cgroupの`memory.peak`は66.5GiBまで伸びるが、
      # その大半はmmapしたモデルファイルのページキャッシュなので、
      # 圧力がかかればカーネルが回収でき、同期回収に張り付くことはない。
      #
      # 下げる余地はあるが下げない。
      # `--fast-disk`はページキャッシュに重みが乗っていることで速度を保つ構造で、
      # 締めるとディスクからの再読み込みが増えて生成が遅くなる。
      # 回収可能なページキャッシュはホスト側が要求すればカーネルが取り返すため、
      # 緩いままでもホストは困らない。
      #
      # ただしこの上限はホスト保護の保証にはならない。
      # 回収できないメモリを抱えた場合は、
      # `MemoryMax`へ達する前にホスト全体のRAMが尽きてglobal OOMになる。
      # pinned memoryが常駐していた頃のOOMが実際にそうだった。
      MemoryHigh = "85%"; # ソフトリミット。これを超えるとメモリを積極的に解放する。
      MemoryMax = "90%"; # ハードリミット。超えたらcgroupの中でOOM killする。
    };
    # bind mountするデータディレクトリをホスト側で用意する。
    tmpfiles.rules = [ "d ${dataDir} 0750 comfyui comfyui - -" ];
  };
}
