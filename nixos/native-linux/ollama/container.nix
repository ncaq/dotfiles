# Ollamaを動かすNixOS Containerの定義。
{
  lib,
  pkgs,
  config,
  hostName,
  username,
  ...
}:
let
  port = 11434;
  hostAddress = "192.168.100.20";
  localAddress = "192.168.100.21";
  ollamaUid = 501;
  ollamaGid = ollamaUid;
  dataDir = "/var/lib/ollama";
  enableCuda = hostName == "bullet";
  package = if enableCuda then pkgs.ollama-cuda else pkgs.ollama-cpu;
  model = if enableCuda then "qwen3.6:27b" else "qwen3.5:9b";
  nvidiaDevices = [
    "/dev/nvidia-modeset"
    "/dev/nvidia-uvm"
    "/dev/nvidia-uvm-tools"
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
    # モデルを永続化し、privateUsersによるUID変換後も固定UIDで読み書きできるようにする。
    extraFlags = [ "--bind=${dataDir}:${dataDir}:idmap" ];
    config =
      { lib, ... }:
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
          openFirewall = true; # コンテナなので無制限公開ではない。
          loadModels = [ model ];
          syncModels = true;
          environmentVariables = {
            OLLAMA_KEEP_ALIVE = "15m";
          };
        };
      };
  };

  systemd = {
    services."container@ollama".serviceConfig = {
      # OSや他の処理のために2スレッド分を残す既存のCPU予算を使う。
      CPUQuota = "${toString (config.local.cpuBudgetThreads * 100)}%";
      MemoryHigh = "50%";
      MemoryMax = "60%";
    };
    tmpfiles.rules = [ "d ${dataDir} 0750 ollama ollama - -" ];
  };

  boot.kernelModules = lib.optionals enableCuda [ "nvidia_uvm" ];
  networking = {
    nat = {
      enable = true;
      internalInterfaces = [ "ve-+" ];
    };
    networkmanager.unmanaged = [ "interface-name:ve-*" ];
  };
}
