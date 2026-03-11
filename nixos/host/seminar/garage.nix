{
  pkgs,
  config,
  ...
}:
let
  addr = config.machineAddresses.garage;
  user = config.containerUsers.garage;
  garageUser = {
    inherit (user) uid;
    group = "garage";
    isSystemUser = true;
  };
  garageWithEnv = pkgs.writeShellApplication {
    name = "garage-runner";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
    ];
    text = ''
      export "$(cat /etc/garage.env | xargs)"
      exec garage "$@"
    '';
  };
  # Host wrapper to execute garage CLI inside the container.
  # Export the environment file to provide GARAGE_RPC_SECRET etc.
  garageWrapper = pkgs.writeShellApplication {
    name = "garage";
    runtimeInputs = with pkgs; [
      nixos-container
    ];
    text = ''
      exec nixos-container run garage -- ${garageWithEnv} "$@"
    '';
  };
in
{
  containers.garage = {
    autoStart = true;
    ephemeral = true;
    privateNetwork = true;
    hostAddress = addr.host;
    localAddress = addr.guest;
    bindMounts = {
      "/etc/garage.env" = {
        hostPath = config.sops.secrets."garage-env".path;
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
        system.stateVersion = "25.11";
        networking = {
          useHostResolvConf = lib.mkForce false;
          firewall.allowedTCPPorts = [ 3900 ];
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
              s3_web = {
                bind_addr = "127.0.0.1:3902";
                root_domain = ".web.garage.ncaq.net";
              };
              admin = {
                api_bind_addr = "127.0.0.1:3903";
              };
            };
          };
        };
        # Override DynamicUser to use explicit UIDs matching host bind-mount ownership.
        # Re-enable security settings that DynamicUser=true would implicitly activate.
        systemd.services.garage.serviceConfig = {
          DynamicUser = lib.mkForce false;
          User = "garage";
          Group = "garage";
          ProtectSystem = "strict";
          PrivateTmp = true;
          RestrictSUIDSGID = true;
          RemoveIPC = true;
        };
        environment.systemPackages = [ pkgs.garage_2 ];
      };
  };

  users = {
    users.garage = garageUser;
    groups.garage.gid = user.gid;
  };

  systemd = {
    tmpfiles.rules = [
      "d /var/lib/garage      0750 garage garage -"
      "d /var/lib/garage/meta 0750 garage garage -"
    ];
    # /mnt/noa is owned by ncaq, so systemd-tmpfiles refuses to create
    # subdirectories owned by garage due to "unsafe path transition" detection.
    # Use ExecStartPre instead.
    services."container@garage".serviceConfig.ExecStartPre = [
      "+${pkgs.writeShellScript "garage-create-data-dir" ''
        install -d -m 0750 -o garage -g garage /mnt/noa/garage
        install -d -m 0750 -o garage -g garage /mnt/noa/garage/data
      ''}"
    ];
  };

  environment.systemPackages = [ garageWrapper ];
  _module.args.garageWrapper = garageWrapper;

  # Managed by sops-nix.
  # To create (first time only):
  # ```
  # RPC_SECRET=$(openssl rand -hex 32)
  # ADMIN_TOKEN=$(openssl rand -base64 32)
  # METRICS_TOKEN=$(openssl rand -base64 32)
  # ```
  # Then `sops secrets/seminar/garage.yaml` and set garage_env to:
  # ```
  # GARAGE_RPC_SECRET="<hex>"
  # GARAGE_ADMIN_TOKEN="<base64>"
  # GARAGE_METRICS_TOKEN="<base64>"
  # ```
  sops.secrets."garage-env" = {
    sopsFile = ../../../secrets/seminar/garage.yaml;
    key = "garage_env";
    owner = "garage";
    group = "garage";
    mode = "0400";
  };

  # Initial cluster setup (manual, first time only):
  # ```
  # sudo garage status
  # sudo garage layout assign <node-id> -z seminar -c 8T
  # sudo garage layout apply --version 1
  # ```
}
