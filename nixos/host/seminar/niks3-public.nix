{
  pkgs,
  config,
  inputs,
  garageWrapper,
  ...
}:
let
  addr = config.machineAddresses.niks3-public;
  user = config.containerUsers.niks3-public;
  niks3User = {
    inherit (user) uid;
    group = "niks3-public";
    isSystemUser = true;
  };
in
{
  containers.niks3-public = {
    autoStart = true;
    ephemeral = true;
    privateNetwork = true;
    hostAddress = addr.host;
    localAddress = addr.guest;
    bindMounts = {
      "/run/postgresql" = {
        hostPath = "/run/postgresql";
        isReadOnly = true;
      };
      "/etc/niks3-public/s3-access-key" = {
        hostPath = config.sops.secrets."niks3-public-s3-access-key".path;
        isReadOnly = true;
      };
      "/etc/niks3-public/s3-secret-key" = {
        hostPath = config.sops.secrets."niks3-public-s3-secret-key".path;
        isReadOnly = true;
      };
      "/etc/niks3-public/api-token" = {
        hostPath = config.sops.secrets."niks3-public-api-token".path;
        isReadOnly = true;
      };
      "/etc/niks3-public/sign-key" = {
        hostPath = config.sops.secrets."niks3-public-sign-key".path;
        isReadOnly = true;
      };
    };
    config =
      { lib, ... }:
      {
        imports = [ inputs.niks3.nixosModules.niks3 ];
        system.stateVersion = "25.11";
        networking = {
          useHostResolvConf = lib.mkForce false;
          firewall.allowedTCPPorts = [ 5751 ];
        };
        users = {
          users.niks3-public = niks3User;
          groups.niks3-public.gid = user.gid;
        };
        services = {
          resolved.enable = true;
          niks3 = {
            enable = true;
            user = "niks3-public";
            group = "niks3-public";
            httpAddr = "[::]:5751";
            database = {
              createLocally = false;
              connectionString = "postgres:///niks3-public?host=/run/postgresql";
            };
            s3 = {
              endpoint = "garage.ncaq.net";
              bucket = "niks3-public";
              region = "garage";
              useSSL = true;
              accessKeyFile = "/etc/niks3-public/s3-access-key";
              secretKeyFile = "/etc/niks3-public/s3-secret-key";
            };
            apiTokenFile = "/etc/niks3-public/api-token";
            signKeyFiles = [ "/etc/niks3-public/sign-key" ];
            cacheUrl = "https://niks3-public.ncaq.net";
            readProxy.enable = true;
            oidc.providers.github = {
              issuer = "https://token.actions.githubusercontent.com";
              audience = "https://niks3-public.ncaq.net";
              boundClaims = {
                repository_owner = [ "ncaq" ];
              };
            };
          };
        };
      };
  };

  users = {
    users.niks3-public = niks3User;
    groups.niks3-public.gid = user.gid;
  };

  systemd.services = {
    "container@niks3-public" = {
      requires = [ "postgresql.service" ];
      after = [ "postgresql.service" ];
    };
    # Garage bucket setup for niks3-public.
    # Idempotently creates the S3 key, bucket, and permissions.
    garage-setup-niks3-public = {
      description = "Setup Garage bucket and key for niks3-public";
      requires = [ "container@garage.service" ];
      after = [ "container@garage.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.lib.getExe (
          pkgs.writeShellApplication {
            name = "garage-setup-niks3-public";
            runtimeInputs = [ garageWrapper ];
            text = ''
              # Wait for garage to be ready.
              for _ in $(seq 1 30); do
                if garage status > /dev/null 2>&1; then
                  break
                fi
                sleep 2
              done

              ACCESS_KEY=$(cat ${config.sops.secrets."niks3-public-s3-access-key".path})
              SECRET_KEY=$(cat ${config.sops.secrets."niks3-public-s3-secret-key".path})

              # Import key (ignore error if key already exists).
              garage key import "$ACCESS_KEY" "$SECRET_KEY" || true

              # Create bucket (ignore error if bucket already exists).
              garage bucket create niks3-public || true

              # Grant permissions.
              garage bucket allow --read --write --owner niks3-public --key "$ACCESS_KEY"
            '';
          }
        );
      };
    };
  };

  # Managed by sops-nix.
  # To create (first time only):
  # ```
  # S3_ACCESS_KEY=$(openssl rand -hex 12)
  # S3_SECRET_KEY=$(openssl rand -hex 24)
  # API_TOKEN=$(openssl rand -base64 36)
  # nix key generate-secret --key-name niks3-public.ncaq.net-1 > /tmp/niks3-sign-key
  # nix key convert-secret-to-public < /tmp/niks3-sign-key
  # ```
  # Then `sops secrets/seminar/niks3-public.yaml` and set:
  # ```
  # s3_access_key: "<hex>"
  # s3_secret_key: "<hex>"
  # api_token: "<base64>"
  # sign_key: "niks3-public.ncaq.net-1:<base64>"
  # ```
  # The public key output from `nix key convert-secret-to-public` should be added
  # to nix.conf as `trusted-public-keys` on clients.
  sops.secrets = {
    "niks3-public-s3-access-key" = {
      sopsFile = ../../../secrets/seminar/niks3-public.yaml;
      key = "s3_access_key";
      owner = "niks3-public";
      group = "niks3-public";
      mode = "0400";
    };
    "niks3-public-s3-secret-key" = {
      sopsFile = ../../../secrets/seminar/niks3-public.yaml;
      key = "s3_secret_key";
      owner = "niks3-public";
      group = "niks3-public";
      mode = "0400";
    };
    "niks3-public-api-token" = {
      sopsFile = ../../../secrets/seminar/niks3-public.yaml;
      key = "api_token";
      owner = "niks3-public";
      group = "niks3-public";
      mode = "0400";
    };
    "niks3-public-sign-key" = {
      sopsFile = ../../../secrets/seminar/niks3-public.yaml;
      key = "sign_key";
      owner = "niks3-public";
      group = "niks3-public";
      mode = "0400";
    };
  };
}
