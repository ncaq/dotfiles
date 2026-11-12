# shellcheck shell=bash
# `writeShellApplication`が先頭にシェバンと`set -euo pipefail`を付けます。
#
# 引数に渡したSKILL.mdのうち、
# `allowed-tools`が範囲の無い`Bash`を許可しているものを報告します。
#
# スキルの`allowed-tools`は、そのスキルの間は`permissions.allow`の一覧に関係なく許可を広げます。
# 範囲の無い`Bash`を許可するスキルが入ると、任意のコマンドを実行できてしまいます。
#
# 終了コードは、検出が無ければ0、検出したら3です。
# ファイルが読めないなどの処理の失敗は`set -e`により、
# awkの2やyqの1のような各コマンドの終了コードで終わります。
# 呼び出し側が検出と処理の失敗を区別できるよう、検出には専用の値を使います。

detected=0
for skill in "$@"; do
  # 先頭の`---`から次の`---`までがYAMLのfrontmatterです。
  # CRLFの改行でも区切りを見つけられるよう、行末の`\r`を落とします。
  frontmatter=$(
    awk '
      { sub(/\r$/, "") }
      NR == 1 && $0 == "---" { inside = 1; next }
      inside && $0 == "---" { exit }
      inside { print }
    ' "$skill"
  )
  # `allowed-tools`はYAMLのリストか、文字列で書かれます。
  # リストは要素ごとに1行で出し、文字列はそのまま出して後で分けます。
  entries=$(
    printf '%s\n' "$frontmatter" | yq '
      .["allowed-tools"]
      | ((select(tag == "!!seq") | .[]), (select(tag == "!!str")))
    '
  )
  # 文字列の一覧はカンマ区切りでも空白区切りでも書けます。
  # `Bash(git log:*)`のように括弧の中にも空白があるので、括弧の外の区切りだけで分けます。
  tools=$(
    printf '%s\n' "$entries" | awk '
      {
        depth = 0
        token = ""
        for (i = 1; i <= length($0); i++) {
          c = substr($0, i, 1)
          if (c == "(") depth++
          if (c == ")" && 0 < depth) depth--
          if (depth == 0 && (c == "," || c == " " || c == "\t")) {
            if (token != "") print token
            token = ""
          } else {
            token = token c
          }
        }
        if (token != "") print token
      }
    '
  )
  while IFS= read -r tool; do
    case "$tool" in
    Bash | 'Bash(*)' | 'Bash(*:*)')
      echo "$skill が範囲の無いBashを許可しています: $tool" >&2
      detected=1
      ;;
    esac
  done <<<"$tools"
done
if [ "$detected" -ne 0 ]; then
  exit 3
fi
