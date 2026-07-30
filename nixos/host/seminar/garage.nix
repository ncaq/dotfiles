{
  pkgs,
  lib,
  config,
  ...
}:
let
  addr = config.machineAddresses.garage;
  user = config.serviceUser.garage;
  garageUser = {
    inherit (user) uid;
    group = "garage";
    isSystemUser = true;
  };
  garageWithEnv = pkgs.writeShellApplication {
    name = "garage-with-env";
    runtimeInputs = [ ];
    text = ''
      set -a
      # shellcheck source=/dev/null
      source /etc/garage.env
      set +a
      exec garage "$@"
    '';
  };
  # コンテナ内のgarage CLIをホストから実行するためのラッパー。
  # GARAGE_RPC_SECRETなどを渡すために環境ファイルをexportする。
  garageWrapper = pkgs.writeShellApplication {
    name = "garage";
    runtimeInputs = with pkgs; [
      nixos-container
    ];
    text = ''
      exec nixos-container run garage -- ${lib.getExe garageWithEnv} "$@"
    '';
  };
in
{
  containers.garage = {
    autoStart = true;
    ephemeral = true;
    privateNetwork = true;
    privateUsers = "identity";
    hostAddress = addr.host;
    localAddress = addr.guest;
    bindMounts = {
      "/etc/garage.env" = {
        hostPath = config.sops.templates."garage-env".path;
        isReadOnly = true;
      };
      "/var/lib/garage/meta" = {
        hostPath = "/var/lib/garage/meta";
        isReadOnly = false;
      };
      "/mnt/noa/garage/data" = {
        hostPath = "/mnt/noa/garage/data";
        isReadOnly = false;
      };
    };
    config =
      { lib, ... }:
      {
        system.stateVersion = "26.05";
        networking = {
          useHostResolvConf = lib.mkForce false;
          firewall.allowedTCPPorts = [
            3900 # S3 API
            3903 # Admin API (プライベートネットワーク経由でホストからのみアクセス)
          ];
        };
        users = {
          users.garage = garageUser;
          groups.garage.gid = user.gid;
        };
        services = {
          resolved.enable = true;
          garage = {
            enable = true;
            package = pkgs.garage_2;
            environmentFile = "/etc/garage.env";
            settings = {
              metadata_dir = "/var/lib/garage/meta";
              data_dir = "/mnt/noa/garage/data";
              db_engine = "lmdb";
              metadata_auto_snapshot_interval = "6h";
              replication_factor = 1;
              rpc_bind_addr = "127.0.0.1:3901";
              s3_api = {
                s3_region = "garage";
                api_bind_addr = "[::]:3900";
                root_domain = ".garage.ncaq.net";
              };
              admin = {
                api_bind_addr = "[::]:3903";
              };
            };
          };
        };
        # ホスト側bind mountの所有権と一致する明示的なUIDを使うためDynamicUserを無効化する。
        # DynamicUser=trueが暗黙に有効化していたセキュリティ設定を再有効化し、
        # さらに追加のハードニングを上乗せする。
        # GarageはRustバイナリで、必要なのはS3/RPC/Admin APIのTCP通信と、
        # bind mountされたmetadata_dirとdata_dirへのファイルアクセスだけ。
        # これらは上流モジュールのStateDirectory/ReadWritePathsで書き込み可能になっている。
        systemd.services.garage.serviceConfig = {
          DynamicUser = lib.mkForce false;
          User = "garage";
          Group = "garage";
          ProtectSystem = "strict";
          PrivateTmp = true;
          RestrictSUIDSGID = true;
          RemoveIPC = true;
          # 空リストはNixOSモジュールがディレクティブごと省略してしまうため、
          # 空文字列でbounding setを空集合にリセットする。
          CapabilityBoundingSet = "";
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          PrivateDevices = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
          ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [ "@system-service" ];
        };
        environment.systemPackages = [ pkgs.garage_2 ];
      };
  };

  users = {
    users.garage = garageUser;
    groups.garage.gid = user.gid;
  };

  systemd = {
    services."container@garage" = {
      requires = [ "sops-install-secrets.service" ];
      after = [ "sops-install-secrets.service" ];
    };
    tmpfiles.rules = [
      "d /var/lib/garage      0750 garage garage -"
      "d /var/lib/garage/meta 0750 garage garage -"
      "d /mnt/noa/garage      0750 garage garage -"
      "d /mnt/noa/garage/data 0750 garage garage -"
    ];
  };

  environment.systemPackages = [ garageWrapper ];

  sops = {
    templates."garage-env" = {
      content = ''
        GARAGE_RPC_SECRET="${config.sops.placeholder."garage-rpc-secret"}"
        GARAGE_ADMIN_TOKEN="${config.sops.placeholder."garage-admin-token"}"
        GARAGE_METRICS_TOKEN="${config.sops.placeholder."garage-metrics-token"}"
      '';
      owner = "garage";
      group = "garage";
      mode = "0400";
    };
    # sops-nixで管理している。
    # 作成方法(初回のみ):
    # ```
    # rpc_secret=$(openssl rand -hex 32)
    # admin_token=$(openssl rand -base64 32)
    # metrics_token=$(openssl rand -base64 32)
    # ```
    # その後`sops secrets/seminar/garage.yaml`で以下を設定する:
    # ```
    # rpc_secret: <hex>
    # admin_token: <base64>
    # metrics_token: <base64>
    # ```
    secrets = {
      "garage-rpc-secret" = {
        sopsFile = ../../../secrets/seminar/garage.yaml;
        key = "rpc_secret";
        owner = "garage";
        group = "garage";
        mode = "0400";
      };
      "garage-admin-token" = {
        sopsFile = ../../../secrets/seminar/garage.yaml;
        key = "admin_token";
        owner = "garage";
        group = "garage";
        mode = "0400";
      };
      "garage-metrics-token" = {
        sopsFile = ../../../secrets/seminar/garage.yaml;
        key = "metrics_token";
        owner = "garage";
        group = "garage";
        mode = "0400";
      };
    };
  };

  # クラスタの初期セットアップ(手動、初回のみ):
  # ```
  # sudo garage status
  # sudo garage layout assign <node-id> -z seminar -c 8T
  # sudo garage layout apply --version 1
  # ```
}
