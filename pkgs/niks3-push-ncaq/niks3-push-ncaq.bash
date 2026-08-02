#!/usr/bin/env bash
set -euo pipefail

# sopsで暗号化されたシークレットファイルからAPIトークンを復号して、
# `niks3 push`を実行する共通ラッパー。
#
# `niks3`の`--auth-token-script`機能を使い、`niks3`が必要なタイミングで、
# `sops decrypt`を呼び出してトークンを取得します。
# 一時ファイルを作らないので、シグナル受信時のクリーンアップ漏れがありません。
# 長期トークンなので`expires_at`は遠い未来に固定し、再取得を防ぎます。
#
# このスクリプトは`niks3-push-ncaq-public`/`niks3-push-ncaq-private`から呼び出されます。
# 各ラッパーが`NIKS3_PUSH_NCAQ_SECRETS_FILE`と`NIKS3_PUSH_NCAQ_SERVER_URL`を設定します。
#
# 引数があればそのまま`niks3 push`にstoreパスとして渡します。
# 引数がなければ標準入力からstoreパスを1行ずつ読みます。

secrets_file=${NIKS3_PUSH_NCAQ_SECRETS_FILE:?NIKS3_PUSH_NCAQ_SECRETS_FILE is not set}
server_url=${NIKS3_PUSH_NCAQ_SERVER_URL:?NIKS3_PUSH_NCAQ_SERVER_URL is not set}

if [ ! -f "$secrets_file" ]; then
  echo "Error: secrets file not found: $secrets_file" >&2
  echo "Set NIKS3_PUSH_NCAQ_SECRETS_FILE to override." >&2
  exit 1
fi

if [ $# -eq 0 ]; then
  mapfile -t paths
  set -- "${paths[@]}"
fi

# `--auth-token-script`に渡すコマンドを組み立てる。
# `niks3`はこの文字列をPOSIXシェル風に単語分割して`exec`するので、
# パイプを使うために`sh -c <script>`の形でラップする。
# stdoutに`{token, expires_at}`JSONを書き出す。
# `sops decrypt`の末尾改行は`rtrimstr("\n")`で除去する。
quoted_secrets_file=$(printf '%q' "$secrets_file")
inner_script=$(
  cat <<SCRIPT
sops decrypt --extract '["api_token"]' ${quoted_secrets_file}
  | jq -Rsc --arg expires '2099-12-31T23:59:59Z'
    '{token: rtrimstr("\n"), expires_at: \$expires}'
SCRIPT
)
# `printf '%q'`が改行を含む文字列を`$'...'`形式でエスケープすると、
# `niks3`の`shellSplit`が解釈できないので、改行をスペースに置換して1行化する。
inner_script=${inner_script//$'\n'/ }
token_command="sh -c $(printf '%q' "$inner_script")"

exec niks3 push \
  --server-url "$server_url" \
  --auth-token-script "$token_command" \
  "$@"
