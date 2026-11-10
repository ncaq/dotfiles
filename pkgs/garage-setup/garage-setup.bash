#!/usr/bin/env bash
set -euo pipefail

# GarageのS3バケットとキーを用意するスクリプト。
#
# 起動のたびに新しいキーを作成し、バケットに権限を付与します。
# バケットは既にあればそれを使い、無ければ作成します。
# キーは使い捨てで、古いキーは触らず期限切れを待ちます。
#
# 環境変数:
#   GARAGE_SETUP_NAME             バケットのグローバルエイリアス。
#                                 キーの名前と、キーファイルを渡すユーザとグループの名前も兼ねます。
#   GARAGE_SETUP_API              GarageのAdmin APIのURL。
#   GARAGE_SETUP_ADMIN_TOKEN_FILE Admin APIのトークンが書かれたファイル。
#   RUNTIME_DIRECTORY             キーファイルを書き出すディレクトリ。
#                                 systemdの`RuntimeDirectory`が設定します。

name=${GARAGE_SETUP_NAME:?GARAGE_SETUP_NAME is not set}
garage_api_url=${GARAGE_SETUP_API:?GARAGE_SETUP_API is not set}
admin_token_file=${GARAGE_SETUP_ADMIN_TOKEN_FILE:?GARAGE_SETUP_ADMIN_TOKEN_FILE is not set}
runtime_directory=${RUNTIME_DIRECTORY:?RUNTIME_DIRECTORY is not set}

admin_token=$(cat "$admin_token_file")

garage_api() {
  curl --fail --silent --show-error \
    --request "$1" "$garage_api_url$2" \
    -H "Authorization: Bearer $admin_token" \
    -H "Content-Type: application/json" \
    ${3:+-d "$3"}
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

# Calculate expiration date (3 months from now) in RFC 3339 format.
expiration=$(date -u -d '+90 days' '+%Y-%m-%dT%H:%M:%SZ')

# Create a new ephemeral key via admin API.
create_key_payload=$(jq -nc \
  --arg name "$name" \
  --arg expiration "$expiration" \
  '{$name, $expiration}')
key_json=$(garage_api POST /v2/CreateKey "$create_key_payload")

access_key=$(echo "$key_json" | jq -r '.accessKeyId')
secret_key=$(echo "$key_json" | jq -r '.secretAccessKey')

if [ -z "$access_key" ] || [ "$access_key" = "null" ] ||
  [ -z "$secret_key" ] || [ "$secret_key" = "null" ]; then
  echo "Failed to create S3 key for $name via Garage admin API" >&2
  exit 1
fi

# Write keys to runtime directory for the client container.
(
  umask 0377
  echo -n "$access_key" >"$runtime_directory/s3-access-key"
  echo -n "$secret_key" >"$runtime_directory/s3-secret-key"
)
chown "$name:$name" \
  "$runtime_directory/s3-access-key" \
  "$runtime_directory/s3-secret-key"

# Get existing bucket or create a new one.
if bucket_json=$(garage_api GET "/v2/GetBucketInfo?globalAlias=$name" 2>/dev/null); then
  bucket_id=$(echo "$bucket_json" | jq -r '.id')
else
  create_bucket_payload=$(jq -nc --arg globalAlias "$name" '{$globalAlias}')
  bucket_json=$(garage_api POST /v2/CreateBucket "$create_bucket_payload")
  bucket_id=$(echo "$bucket_json" | jq -r '.id')
fi

# Grant read/write permissions.
allow_payload=$(jq -nc \
  --arg bucketId "$bucket_id" \
  --arg accessKeyId "$access_key" \
  '{$bucketId, $accessKeyId, permissions: {read: true, write: true}}')
garage_api POST /v2/AllowBucketKey "$allow_payload" >/dev/null

# 未完了マルチパートアップロードを2日後に自動abortするlifecycleルールを設定する。
# 未完了マルチパートが溜まり続けるとメタデータDB(LMDB)が肥大化する。
# Garage組み込みのlifecycle workerに、
# 日々掃除させ負荷を平準化する。
# (UTC 0時に100件ずつバッチ実行、batch sizeと頻度はソースに固定されている)
# アプリケーション側のGCと喧嘩しにくいように、
# 期限は長めの2日後に設定する。
lifecycle_payload=$(jq -nc \
  '{
    lifecycleRules: [
      {
        ID: "abort-incomplete-multipart-upload",
        Status: "Enabled",
        Filter: { Prefix: "" },
        AbortIncompleteMultipartUpload: { DaysAfterInitiation: 2 }
      }
    ]
  }')
garage_api POST "/v2/UpdateBucket?id=$bucket_id" "$lifecycle_payload" >/dev/null
