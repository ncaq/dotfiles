# Ollamaを動かすNixOS Containerの定義。
{
  lib,
  pkgs-unstable,
  config,
  username,
  ...
}:
let
  port = 11434;
  # コンテナのvethのアドレス。
  # ホストとの間はIPv6で繋ぐ。
  # seminarではホストの`machineAddresses`にも同じ値を予約している。
  hostAddress6 = "fdf2:a855:5a3f:100::20";
  localAddress6 = "fdf2:a855:5a3f:100::21";
  # IPv4は出口のためだけに持たせる(下の`local.machineEgress`を参照)。
  toAddress4 = ipv6: import ../../lib/machine-address4.nix { inherit lib ipv6; };
  hostAddress = toAddress4 hostAddress6;
  localAddress = toAddress4 localAddress6;
  ollamaUid = 501;
  ollamaGid = ollamaUid;
  dataDir = config.local.ollama.dataDir;
  enableCuda = config.local.ollama.enableCuda;
  # 古いOllamaでは`ollama pull`が412で拒否されることがあるため、
  # unstableのOllamaを使う。
  package = if enableCuda then pkgs-unstable.ollama-cuda else pkgs-unstable.ollama-cpu;
  # 推論に必要な最小限だけを渡す。
  # NVIDIAのcharデバイスはioctl経由の攻撃面が広く、
  # このコンテナは認証のないHTTP APIをtailnetへ公開しているため、
  # モード設定用の`nvidia-modeset`とデバッグ用の`nvidia-uvm-tools`は渡さない。
  nvidiaDevices = [
    "/dev/nvidia-uvm"
    "/dev/nvidia0"
    "/dev/nvidiactl"
  ];
in
{
  users = {
    users = {
      ollama = {
        uid = ollamaUid;
        group = "ollama";
        isSystemUser = true;
      };
      ${username}.extraGroups = [ "ollama" ];
    };
    groups.ollama.gid = ollamaGid;
  };

  containers.ollama = {
    # ホスト側のsocketへの初回アクセスで起動する。
    autoStart = false;
    ephemeral = true;
    privateNetwork = true;
    privateUsers = "pick";
    inherit
      hostAddress
      localAddress
      hostAddress6
      localAddress6
      ;
    allowedDevices = lib.optionals enableCuda (
      map (node: {
        inherit node;
        modifier = "rw";
      }) nvidiaDevices
    );
    bindMounts = lib.mkIf enableCuda (
      lib.genAttrs nvidiaDevices (device: {
        hostPath = device;
        isReadOnly = false;
      })
      // {
        "/run/opengl-driver" = {
          hostPath = "/run/opengl-driver";
          isReadOnly = true;
        };
      }
    );
    # 可変データを永続化し、
    # privateUsersによるUID変換後も固定UIDで読み書きできるようにする。
    extraFlags = [ "--bind=${dataDir}:${dataDir}:idmap" ];
    config =
      { lib, pkgs, ... }:
      {
        system.stateVersion = "26.05";
        time.timeZone = "Asia/Tokyo";
        networking.useHostResolvConf = lib.mkForce false;
        services.resolved.enable = true;
        users = {
          users.ollama.uid = ollamaUid;
          groups.ollama.gid = ollamaGid;
        };
        services.ollama = {
          enable = true;
          inherit package;
          user = "ollama";
          group = "ollama";
          # ホストからはIPv6で繋ぐ。
          host = "[::]";
          inherit port;
          # コンテナのIPはホスト内に閉じているため、tailnet外のLANからは到達できない。
          # 他のコンテナからはホストの`local.machineEgress`でこのアドレスを宛先に許した時だけ届く。
          # ComfyUIなどから推論を利用する構想があるため、
          # その時にコンテナ側で開け直さなくて済むようにこちらは開けておく。
          openFirewall = true;
          loadModels = config.local.ollama.loadModels;
          syncModels = false; # オンデマンド追加したモデルを残す。
          environmentVariables = {
            # GPUのホストはVRAMは貴重なので、
            # 使わなくなったらすぐにVRAMを解放する。
            # CPUのホストはメインメモリは大して貴重ではないので、
            # ディスクから読み直すのが嫌なので長く保つ。
            OLLAMA_KEEP_ALIVE = if enableCuda then "5m" else "15m";
            # Ollamaの既定は4096で、長い文書やコードを扱う時に足りない。
            # KVキャッシュはnum_ctxの分を先に確保するので常にメモリを消費する。
            # bulletでの実測では、
            # `qwen3.8:27b-mtp-q4_K_M`が131072でも27GiBに収まって全層がGPUに載り、
            # 生成速度は32768の時と変わらなかった。
            # モデルの上限である262144まで伸ばすとVRAMから溢れて速度が1/4になる。
            # CUDAのホストの147456は、
            # 汎用と自由度優先の全てのモデルが全層GPUに載り、
            # VRAMの空きを0.5GiB以上残せる最大の長さである。
            # bulletでの実測(KVキャッシュq8_0)は以下の通り。
            # - `qwen3.8-27b-mtp:q6_k`: 163840まで速度は129トークン/秒のまま全層が載り、180224で9%がCPUへ溢れて76トークン/秒
            # - `qwen3.8-27b-heretic-rvn:q6_k`: 163840でも全層が載り、VRAMの空きは0.9GiB
            # - `gemma4-31b-mtp:q4_k_m`: 147456でVRAMの空きは1.1GiBだが、163840では0.15GiBしか残らない
            # Qwen3.8だけ163840にする手もあるが、
            # モデルごとに長さが変わるとハーネスへ伝える値もモデルごとに分ける必要があるので、
            # 全てのモデルで共通の長さにしている。
            # CPU推論のホストでは伸ばしても生成速度は落ちない。
            # seminarでの実測では`qwen3.6:35b-a3b`が4096で21.4GiB、
            # 262144でも27.5GiBで、生成速度はどちらも約18トークン/秒だった。
            # 制約になるのはコンテナのMemoryHigh(全体の50%で約31GiB)の方である。
            # 32768という値は、
            # 今は無い即答性を優先した役割のモデルを、
            # 汎用モデルと同時に常駐させていた頃の実測で決めた。
            # 当時のseminarでは、
            # 32768なら両方載せてcgroupの実測が約29GiBで収まるのに対し、
            # 65536では約30GiBとMemoryHighに張り付いてしまった。
            # 今は対話に使うモデルを同時に載せることは無く、
            # 使う1つだけを載せて他は降ろすので余裕は増えているはずだが、
            # 測り直していない。
            # 値そのものはクライアント側も必要とするのでオプションが持っている。
            OLLAMA_CONTEXT_LENGTH = toString config.local.ollama.contextLength;
          }
          // lib.optionalAttrs enableCuda {
            # KVキャッシュをq8_0で量子化して、
            # 浮いたVRAMを重みの量子化を上げるのに回す。
            # bulletでの実測(`qwen3.8:27b-mtp-q4_K_M`, context 131072)では、
            # f16の27.1GiBに対しq8_0は23.8GiBで3.3GiB浮き、
            # 生成速度の低下は147から136.8トークン/秒の7%に留まる。
            # 同じ3.3GiBを重みに使うとq4_K_MをQ6_Kまで引き上げられるので、
            # KVを8bitに落とす損失より重みの精度を上げる利得の方が大きい。
            # 量子化にはflash attentionが要るが、
            # Ollamaは対応するモデルとGPUなら自動で有効にする。
            # q4_0まで落とすと更に2GiB浮くものの、
            # 長い文脈での劣化が目に見えるようになるので選ばない。
            # CPU推論のホストへは入れない。
            # メインメモリは貴重ではなく、
            # 量子化と復元の計算コストがそのまま生成速度に効いてしまう。
            OLLAMA_KV_CACHE_TYPE = "q8_0";
          };
        };
        # nixpkgsのOllamaモジュールは固定ユーザを指定してもDynamicUserを有効にするため、
        # bind mountしたStateDirectoryを固定ユーザで扱えるように上書きする。
        systemd.services = {
          ollama.serviceConfig = {
            DynamicUser = lib.mkForce false;
            # StateDirectoryのモードは起動ごとにsystemdが強制するため、
            # tmpfilesで宣言するだけでは既定の0755へ戻されてしまう。
            StateDirectoryMode = "0750";
          };
          ollama-model-loader = {
            # GNU parallelがsystem userのnologin shellを使わないようにする。
            environment.SHELL = lib.getExe pkgs.bash;
            serviceConfig = {
              DynamicUser = lib.mkForce false;
              User = "ollama";
              Group = "ollama";
            };
          };
        };
      };
  };

  systemd = {
    services."container@ollama".serviceConfig = {
      # OSや他の処理のために2スレッド分を残す既存のCPU予算を使う。
      # CPU推論のホストではメモリを大量に使うため、
      # 推論の速度よりホスト全体のメモリ保護を優先する。
      CPUQuota = "${toString (config.local.cpuBudgetThreads * 100)}%";
      MemoryHigh = "50%";
      MemoryMax = "60%";
    };
    tmpfiles.rules = [
      "d ${dataDir} 0750 ollama ollama - -"
      "d ${dataDir}/models 0750 ollama ollama - -"
    ];
  };

  networking = {
    nat = {
      enable = true;
      # ULAを持つコンテナをIPv6で外へ出す(`lib/machine-address4.nix`)。
      enableIPv6 = true;
      internalInterfaces = [ "ve-*" ];
    };
    networkmanager.unmanaged = [ "interface-name:ve-*" ];
  };

  # Ollamaの出口はインターネットだけ。
  # モデルの取得(`ollama pull`)でregistry.ollama.aiへ繋ぐ。
  # 推論のクライアントはTailscale Serviceからホストの中継を経て繋ぎに来る側なので、
  # 自宅LANやtailnetや他のコンテナへ出る理由は無い。
  #
  # registry.ollama.aiとモデルの実体を置くCloudflare R2はIPv6で届くが、
  # 手で`ollama pull hf.co/...`する時のHugging Faceの配信元(cas-bridge.xethub.hf.co)はIPv4にしか無い。
  # そのためにIPv4も持たせている。
  local.machineEgress.ollama.internet = true;
}
