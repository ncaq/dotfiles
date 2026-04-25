#!/usr/bin/env bash
set -euo pipefail

# base(master)とPR側のNix評価結果をnvdで比較し、
# 差分をMarkdownリストに整形してPRコメントとしてupsertします。
#
# 必須環境変数:
#   BASE_REF           PRのベースブランチ名 (例: master)
#   PR_NUMBER          PR番号
#   GITHUB_REPOSITORY  owner/repo
#   GH_TOKEN           PRコメント投稿権限を持つGitHubトークン
#
# 依存しているコマンドを用意すれば単独でも実行可能です。

: "${BASE_REF:?required: base branch}"
: "${PR_NUMBER:?required: PR number}"
: "${GITHUB_REPOSITORY:?required: owner/repo}"
: "${GH_TOKEN:?required: GitHub API token}"

script_dir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
base_tree="$workdir/base"

# base側をworktreeで別ディレクトリに展開します。
# private repoとかで失敗してもGitHub Actionsで取っていれば大丈夫なのでfallbackします。
git fetch --no-tags origin -- "$BASE_REF" || true
# こちらのworktreeは必要なので失敗したら全体失敗です。
git worktree add --detach "$base_tree" -- "origin/$BASE_REF"

# 評価対象はseminarのみ。
# 他ホスト分はノイズが多いため当面は含めません。
# home-managerはseminarのNixOSトップレベルに包含されるため別途は出しません。
host="seminar"
attr=".#nixosConfigurations.\"$host\".config.system.build.toplevel"

# wall-clockを短縮するためbase/PRのnix buildを並列実行します。
# 評価フェーズで一時的にメモリ使用量が増えますが、
# Nixデーモンが共有のロック機構を持っているのでビルド競合は起きません。
# stderrの進捗表示は混ざりますが致命的ではないのでそのままにします。
(cd "$base_tree" && nix build --no-link --print-out-paths "$attr" >"$workdir/before") &
before_pid=$!
nix build --no-link --print-out-paths "$attr" >"$workdir/after" &
after_pid=$!

# `set -e`下での`wait`の挙動はバージョン依存があるため、
# 両方とも明示的にステータスを取って判定します。
before_status=0
after_status=0
wait "$before_pid" || before_status=$?
wait "$after_pid" || after_status=$?
if [ "$before_status" -ne 0 ]; then
  echo "Error: base nix build failed with status $before_status" >&2
  exit "$before_status"
fi
if [ "$after_status" -ne 0 ]; then
  echo "Error: PR nix build failed with status $after_status" >&2
  exit "$after_status"
fi

before=$(<"$workdir/before")
after=$(<"$workdir/after")

MARKER='<!-- nvd-pr-diff -->'
body_file="$workdir/body.md"

# stderrはキャプチャせずにそのまま継承し、CIログ側で確認できるようにします。
if ! raw=$(nvd diff "$before" "$after"); then
  echo "Warning: nvd diff failed" >&2
  printf 'nvd diff failed. See workflow logs for details.\n' >&2
  exit 1
else
  listed=$(printf '%s\n' "$raw" | awk -f "$script_dir/format-for-markdown.awk")
  {
    printf '%s\n' "$MARKER"
    printf '## nvd diff: %s (base: %s)\n\n' "$host" "$BASE_REF"
    printf '%s\n' "$listed"
  } >"$body_file"
fi

# 既存コメントを検索してupsertします。
# `gh pr comment`にはコメント編集機能がないため、
# やむを得ず`gh api`を使用します。
# 使用する機能がある程度固定化されているため、
# そう危険ではないはずです。
existing_id=$(gh api --paginate --slurp \
  "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" |
  jq -r "
    first(
      .[]
      | .[]
      | select(.user.login == \"github-actions[bot]\")
      | select(.body | startswith(\"$MARKER\"))
      | .id
    ) // empty
  ")

if [ -n "$existing_id" ]; then
  jq -n --rawfile body "$body_file" '{body: $body}' |
    gh api --method PATCH \
      "repos/$GITHUB_REPOSITORY/issues/comments/$existing_id" \
      --input - >/dev/null
  echo "Updated comment $existing_id"
else
  gh pr comment "$PR_NUMBER" \
    --repo "$GITHUB_REPOSITORY" \
    --body-file "$body_file"
  echo "Created new comment"
fi
