/**
  Garage S3バケットとキーのセットアップサービスを生成する関数。
  niks3-public, niks3-privateなど、Garageバケットを使うサービスで共用する。
  起動時にidempotentにS3キーを作成し、バケットに権限を付与する。
  キーは使い捨てであり、起動時ごとに新しいキーが生成されます。
  古いキーは触らず捨てて期限切れを待ちます。
  古いキーが蓄積するのは問題にならないと想定しています。
*/
{
  pkgs,
  config,
  name,
}:
{
  description = "Setup Garage bucket and key for ${name}";
  requires = [ "container@garage.service" ];
  after = [ "container@garage.service" ];
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    RuntimeDirectory = "garage-setup/${name}";
    RuntimeDirectoryMode = "0700";
    # Hardening
    CapabilityBoundingSet = [
      "CAP_CHOWN"
      "CAP_DAC_READ_SEARCH"
      "CAP_FOWNER"
    ];
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
    NoNewPrivileges = true;
    PrivateDevices = true;
    PrivateTmp = true;
    ProtectClock = true;
    ProtectControlGroups = true;
    ProtectHome = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectSystem = "strict";
    RestrictAddressFamilies = [
      "AF_INET"
      "AF_INET6"
      "AF_UNIX"
    ];
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    SystemCallArchitectures = "native";
    SystemCallFilter = [
      "@system-service"
      "~@privileged"
      "@chown"
    ];
    ExecStart = pkgs.lib.getExe (
      pkgs.writeShellApplication {
        name = "garage-setup-${name}";
        runtimeInputs = with pkgs; [
          coreutils
          curl
          findutils
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
          garage_ready=false
          for _ in $(seq 1 30); do
            health_output=$(garage_api GET /v2/GetClusterHealth 2>&1) && {
              garage_ready=true
              break
            }
            sleep 2
          done
          if [ "$garage_ready" = false ]; then
            echo "Garage health check timed out. Last response:" >&2
            echo "$health_output" >&2
            exit 1
          fi

          # Calculate expiration date (1 year from now) in RFC 3339 format.
          EXPIRATION=$(date -u -d '+365 days' '+%Y-%m-%dT%H:%M:%SZ')

          # Create a new ephemeral key via admin API.
          KEY_JSON=$(garage_api POST /v2/CreateKey \
            "{\"name\": \"${name}\", \"expiration\": \"$EXPIRATION\"}")

          ACCESS_KEY=$(echo "$KEY_JSON" | jq -r '.accessKeyId')
          SECRET_KEY=$(echo "$KEY_JSON" | jq -r '.secretAccessKey')

          if [ -z "$ACCESS_KEY" ] || [ "$ACCESS_KEY" = "null" ] \
            || [ -z "$SECRET_KEY" ] || [ "$SECRET_KEY" = "null" ]; then
            echo "Failed to create S3 key for ${name} via Garage admin API" >&2
            exit 1
          fi

          # Write keys to runtime directory for ${name} container.
          (
            umask 0377
            echo -n "$ACCESS_KEY" > /run/garage-setup/${name}/s3-access-key
            echo -n "$SECRET_KEY" > /run/garage-setup/${name}/s3-secret-key
          )
          chown ${name}:${name} \
            /run/garage-setup/${name}/s3-access-key \
            /run/garage-setup/${name}/s3-secret-key

          # Get existing bucket or create a new one.
          if BUCKET_JSON=$(garage_api GET "/v2/GetBucketInfo?globalAlias=${name}" 2>/dev/null); then
            BUCKET_ID=$(echo "$BUCKET_JSON" | jq -r '.id')
          else
            BUCKET_JSON=$(garage_api POST /v2/CreateBucket \
              "{\"globalAlias\": \"${name}\"}")
            BUCKET_ID=$(echo "$BUCKET_JSON" | jq -r '.id')
          fi

          # Grant read/write permissions.
          ALLOW_PAYLOAD=$(jq -nc \
            --arg bucketId "$BUCKET_ID" \
            --arg accessKeyId "$ACCESS_KEY" \
            '{$bucketId, $accessKeyId, permissions: {read: true, write: true}}')
          garage_api POST /v2/AllowBucketKey "$ALLOW_PAYLOAD" > /dev/null

          # 未完了マルチパートアップロードを1日後に自動abortするlifecycleルールを設定する。
          # 未完了マルチパートが溜まり続けるとメタデータDB(LMDB)が肥大化する。
          # Garage組み込みのlifecycle worker(既定でUTC 0時に100件ずつバッチ実行)に日々掃除させ、
          # 負荷を平準化する。
          LIFECYCLE_PAYLOAD=$(jq -nc \
            '{lifecycleRules: [
               {
                 ID: "abort-incomplete-multipart-upload",
                 Status: "Enabled",
                 Filter: { Prefix: "" },
                 AbortIncompleteMultipartUpload: { DaysAfterInitiation: 1 }
               }
             ]}')
          garage_api POST "/v2/UpdateBucket?id=$BUCKET_ID" "$LIFECYCLE_PAYLOAD" > /dev/null
        '';
      }
    );
  };
}
