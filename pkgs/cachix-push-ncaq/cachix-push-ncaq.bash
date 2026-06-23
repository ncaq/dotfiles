#!/usr/bin/env bash
set -euo pipefail

# `secrets/cachix.yaml`からCachix認証トークンを復号して、
# `cachix push ncaq`を実行するラッパー。
#
# 自宅サーバのniks3キャッシュが落ちた時のフォールバックとして、
# 別マシンやCIに手軽にキャッシュを転送するために使います。
#
# 引数があればそのまま`cachix push <cache>`に渡します。
# 引数がなければ標準入力からstoreパス一覧を読みます。
#
# 環境変数で挙動を変更できます:
#   CACHIX_PUSH_NCAQ_SECRETS_FILE  sopsで暗号化されたシークレットファイル。
#                                  デフォルトは`$HOME/dotfiles/secrets/cachix.yaml`。
#   CACHIX_PUSH_NCAQ_CACHE         Cachixのキャッシュ名。デフォルトは`ncaq`。

secrets_file=${CACHIX_PUSH_NCAQ_SECRETS_FILE:-$HOME/dotfiles/secrets/cachix.yaml}
cache_name=${CACHIX_PUSH_NCAQ_CACHE:-ncaq}

if [ ! -f "$secrets_file" ]; then
  echo "Error: secrets file not found: $secrets_file" >&2
  echo "Set CACHIX_PUSH_NCAQ_SECRETS_FILE to override." >&2
  exit 1
fi

# トークン取得時のみ環境に露出させ、cachixのサブプロセスに継承させます。
CACHIX_AUTH_TOKEN=$(sops decrypt --extract '["CACHIX_AUTH_TOKEN"]' "$secrets_file")
export CACHIX_AUTH_TOKEN

exec cachix push "$cache_name" "$@"
