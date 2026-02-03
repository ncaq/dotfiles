---
allowed-tools:
  - Bash(gh pr checks:*)
  - Bash(gh pr diff:*)
  - Bash(gh pr list:*)
  - Bash(gh pr status:*)
  - Bash(gh pr view:*)
  - Task
  - mcp__github
  - mcp__github_inline_comment__create_inline_comment
description: Review a pull request
---

# コードレビューの実行

以下の主要領域について専門のサブエージェントを並列で使用して包括的なコードレビューを実行します。

- code-quality-reviewer
- documentation-accuracy-reviewer
- performance-reviewer
- pr-conversation-collector
- security-code-reviewer
- test-coverage-reviewer

各レビューエージェントには特筆すべきフィードバックのみを提供するよう指示します。

# 重複コメントの除外

全サブエージェント完了後、レビューフィードバックを`pr-conversation-collector`の結果と照合し、以下に該当するものは除外します:

- 既に同じ指摘が既存コメントに含まれている
- 指摘に対して「対応しない」「意図的」「仕様」等の返答がある
- 既にresolvedされたレビューコメントと同じ内容

# コメントの投稿

除外後、残った特筆すべきフィードバックのみを投稿します。

具体的な指摘には`mcp__github_inline_comment__create_inline_comment`でインラインコメントを使用してください。
全体的な所感にはトップレベルコメントを使用してください。
フィードバックは簡潔にしてください。

レビューは日本語で行ってください。
