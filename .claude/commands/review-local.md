---
allowed-tools:
  - Bash(gh pr view:*)
  - Bash(gh repo view:*)
  - Bash(git diff:*)
  - Bash(git log:*)
  - Bash(git rev-parse:*)
  - Glob
  - Grep
  - Read
  - Task
  - TodoWrite
description: Review local changes compared to base branch
---

# ベースブランチの特定

1. `gh pr view --json baseRefName --jq .baseRefName`で現在のブランチに紐づくPRのベースブランチを取得
2. PRが存在しない場合(コマンドがエラーになった場合)は、
   `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`でリポジトリのデフォルトブランチを使用

# 差分の取得

1. コミットメッセージ履歴: `git log <base>...HEAD`
2. 最終的な差分: `git diff <base>...HEAD`

# コードレビューの実行

以下の主要領域について専門のサブエージェントを並列で使用して包括的なコードレビューを実行します。

- code-quality-reviewer
- documentation-accuracy-reviewer
- performance-reviewer
- pr-conversation-collector(ベースブランチ特定時に`gh pr view`が成功した場合のみ)
- security-code-reviewer
- test-coverage-reviewer

各レビューエージェントには特筆すべきフィードバックのみを提供するよう指示します。

# 重複コメントの除外

`pr-conversation-collector`の結果がある場合、レビューフィードバックと照合し、以下に該当するものは除外します:

- 既に同じ指摘が既存コメントに含まれている
- 指摘に対して「対応しない」「意図的」「仕様」等の返答がある
- 既にresolvedされたレビューコメントと同じ内容

除外後、残った特筆すべきフィードバックのみを出力します。

# フィードバックの形式

各フィードバックは以下の形式で出力します:

1. ファイルパス
2. 該当箇所の差分(diffフォーマット)
3. コメント

レビューは日本語で行ってください。
