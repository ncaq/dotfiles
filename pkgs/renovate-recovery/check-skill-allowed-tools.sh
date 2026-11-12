# shellcheck shell=bash
# `writeShellApplication`が先頭にシェバンと`set -euo pipefail`を付けます。
#
# 引数に渡したSKILL.mdのうち、
# `allowed-tools`が範囲の無い`Bash`を許可しているものを報告して失敗します。
#
# スキルの`allowed-tools`は、そのスキルの間は`permissions.allow`の一覧に関係なく許可を広げます。
# 範囲の無い`Bash`を許可するスキルが入ると、任意のコマンドを実行できてしまいます。

status=0
for skill in "$@"; do
  # 先頭の`---`から次の`---`までがYAMLのfrontmatterです。
  frontmatter=$(
    awk '
      NR == 1 && $0 == "---" { inside = 1; next }
      inside && $0 == "---" { exit }
      inside { print }
    ' "$skill"
  )
  # `allowed-tools`はカンマ区切りの文字列か、YAMLのリストで書かれます。
  tools=$(
    printf '%s\n' "$frontmatter" | yq '
      .["allowed-tools"]
      | ((select(tag == "!!seq") | .[]), (select(tag == "!!str") | split(",") | .[]))
    '
  )
  while IFS= read -r tool; do
    tool=$(printf '%s' "$tool" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    case "$tool" in
    Bash | 'Bash(*)' | 'Bash(*:*)')
      echo "$skill が範囲の無いBashを許可しています: $tool" >&2
      status=1
      ;;
    esac
  done <<<"$tools"
done
exit "$status"
