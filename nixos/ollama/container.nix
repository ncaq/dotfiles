# Ollamaを動かすNixOS Containerの定義。
{
  lib,
  pkgs,
  config,
  username,
  ...
}:
let
  port = 11434;
  hostAddress = "192.168.100.20";
  localAddress = "192.168.100.21";
  ollamaUid = 501;
  ollamaGid = ollamaUid;
  dataDir = config.local.ollama.dataDir;
  enableCuda = config.local.ollama.enableCuda;
  package = if enableCuda then pkgs.ollama-cuda else pkgs.ollama-cpu;
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
    inherit hostAddress localAddress;
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
          host = "0.0.0.0";
          inherit port;
          # コンテナのIPはホスト内に閉じているため、tailnet外のLANからは到達できない。
          # ホストのFORWARDはACCEPTなので他のコンテナからも到達できるが、
          # ComfyUIなどから推論を利用する構想があるためこれは意図的に許容する。
          openFirewall = true;
          loadModels = config.local.ollama.loadModels;
          syncModels = false; # オンデマンド追加したモデルを残す。
          environmentVariables = {
            OLLAMA_KEEP_ALIVE = "15m";
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
      internalInterfaces = [ "ve-+" ];
    };
    networkmanager.unmanaged = [ "interface-name:ve-*" ];
  };
}
