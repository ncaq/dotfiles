{
  pkgs,
  config,
  inputs,
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
        hostPath = "/run/niks3-public/s3-access-key";
        isReadOnly = true;
      };
      "/etc/niks3-public/s3-secret-key" = {
        hostPath = "/run/niks3-public/s3-secret-key";
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
      requires = [
        "postgresql.service"
        "garage-setup-niks3-public.service"
      ];
      after = [
        "postgresql.service"
        "garage-setup-niks3-public.service"
      ];
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
        RuntimeDirectory = "niks3-public";
        RuntimeDirectoryMode = "0700";
        ExecStart = pkgs.lib.getExe (
          pkgs.writeShellApplication {
            name = "garage-setup-niks3-public";
            runtimeInputs = with pkgs; [
              curl
              jq
            ];
            text = ''
              ADMIN_TOKEN=$(cat ${config.sops.secrets."garage-admin-token".path})
              GARAGE_API="http://${config.machineAddresses.garage.guest}:3903"

              garage_api() {
                curl --fail --silent --show-error \
                  --request "$1" "$GARAGE_API$2" \
                  -H "Authorization: Bearer $ADMIN_TOKEN" \
                  -H "Content-Type: application/json" \
                  ''${3:+-d "$3"}
              }

              # Wait for garage to be ready.
              for _ in $(seq 1 30); do
                if garage_api GET /v2/GetClusterHealth > /dev/null 2>&1; then
                  break
                fi
                sleep 2
              done

              # Calculate expiration date (1 year from now) in RFC 3339 format.
              EXPIRATION=$(date -u -d '+365 days' '+%Y-%m-%dT%H:%M:%SZ')

              # Create a new ephemeral key via admin API.
              KEY_JSON=$(garage_api POST /v2/CreateKey \
                "{\"name\": \"niks3-public\", \"expiration\": \"$EXPIRATION\"}")

              ACCESS_KEY=$(echo "$KEY_JSON" | jq -r '.accessKeyId')
              SECRET_KEY=$(echo "$KEY_JSON" | jq -r '.secretAccessKey')

              if [ -z "$ACCESS_KEY" ] || [ "$ACCESS_KEY" = "null" ] || [ -z "$SECRET_KEY" ] || [ "$SECRET_KEY" = "null" ]; then
                echo "Failed to create key via admin API:" >&2
                echo "$KEY_JSON" >&2
                exit 1
              fi

              # Write keys to runtime directory for niks3-public container.
              (
                umask 0377
                echo -n "$ACCESS_KEY" > /run/niks3-public/s3-access-key
                echo -n "$SECRET_KEY" > /run/niks3-public/s3-secret-key
              )
              chown niks3-public:niks3-public /run/niks3-public/s3-access-key /run/niks3-public/s3-secret-key

              # Create bucket with global alias, or get existing bucket ID.
              if BUCKET_JSON=$(garage_api POST /v2/CreateBucket \
                "{\"globalAlias\": \"niks3-public\"}"); then
                BUCKET_ID=$(echo "$BUCKET_JSON" | jq -r '.id')
              else
                BUCKET_ID=$(garage_api GET "/v2/GetBucketInfo?alias=niks3-public" | jq -r '.id')
              fi

              # Grant read/write permissions.
              garage_api POST /v2/AllowBucketKey \
                "{\"bucketId\": \"$BUCKET_ID\", \"accessKeyId\": \"$ACCESS_KEY\", \"permissions\": {\"read\": true, \"write\": true}}" \
                > /dev/null
            '';
          }
        );
      };
    };
  };

  # Managed by sops-nix.
  # S3 keys are dynamically generated by garage-setup-niks3-public on each boot.
  # To create api_token and sign_key (first time only):
  # ```
  # API_TOKEN=$(openssl rand -base64 36)
  # nix key generate-secret --key-name niks3-public.ncaq.net-1 > /tmp/niks3-sign-key
  # nix key convert-secret-to-public < /tmp/niks3-sign-key
  # ```
  # Then `sops secrets/seminar/niks3-public.yaml` and set:
  # ```
  # api_token: "<base64>"
  # sign_key: "niks3-public.ncaq.net-1:<base64>"
  # ```
  # The public key output from `nix key convert-secret-to-public` should be added
  # to nix.conf as `trusted-public-keys` on clients.
  sops.secrets = {
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
