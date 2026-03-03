---
description: AIがコミットメッセージを生成し、$EDITORで修正してからコミットします
model: sonnet
context: fork
disable-model-invocation: true
allowed-tools:
  - Bash(git add:*)
  - Bash(git commit:*)
  - Bash(git diff:*)
  - Bash(git log:*)
  - Bash(git show:*)
  - Bash(git status:*)
  - Glob
  - Grep
  - Read
  - Write
  - mcp__github__get_file_contents
  - mcp__github__issue_read
  - mcp__github__list_issues
  - mcp__github__list_pull_requests
  - mcp__github__pull_request_read
  - mcp__github__search_code
  - mcp__github__search_issues
  - mcp__github__search_pull_requests
---

Gitリポジトリの変更をコミットします。
AIがコミットメッセージを生成し、
ユーザが`$EDITOR`で修正してからコミットします。

# 手順

## リポジトリ状態の確認

```bash
git status
```

## ステージング

ステージ済みの変更がない場合は全ての変更をステージングします。

```bash
git add --all .
```

既にステージ済みの変更がある場合はそのまま使用します。

## 差分の取得

```bash
git diff --cached
```

差分がなければ「コミットする変更がありません」と報告して終了してください。

## コミットメッセージのガイドラインの確認

プロジェクトルートに`.github/git-commit-instructions.md`が存在する場合はReadツールで読み込んでください。
存在しない場合はスキップしてください。

## 既存コミットスタイルの把握

```bash
git log --oneline -10
```

既存のコミットメッセージのスタイル(Conventional Commitsなど)を把握してください。

## コミットメッセージの生成

ステージ済みの差分を分析し、適切なコミットメッセージを生成してください。

- 既存のコミットスタイルに合わせる
- `.github/git-commit-instructions.md`があればそのガイドラインに従う
- 1行目はタイトルで簡潔に変更の要約
- 必要に応じて空行の後に本文を追加

## 一時ファイルへの書き出し

生成したコミットメッセージをWriteツールで以下のパスに書き出してください。

```
/tmp/coding-agent-work/COMMIT_EDITMSG
```

## コミットの実行

以下のコマンドでコミットを実行します。
`-e`フラグにより`$EDITOR`が起動し、ユーザがメッセージを編集できます。
タイムアウトは600秒(10分)に設定してください。

```bash
git commit -F /tmp/coding-agent-work/COMMIT_EDITMSG -e
```

エディタの起動に失敗した場合は、一時ファイルのパスを案内して手動でのコミットを促してください。

```
コミットメッセージは /tmp/coding-agent-work/COMMIT_EDITMSG に保存されています。
以下のコマンドでコミットできます:
git commit -F /tmp/coding-agent-work/COMMIT_EDITMSG -e
```

## commit-msgフック失敗時の対応

commit-msgフックが失敗した場合、生成したメッセージ自体が合理的であれば`--no-verify`で再試行してください。

```bash
git commit -F /tmp/coding-agent-work/COMMIT_EDITMSG --no-verify
```

メッセージに問題がある場合は修正してから再試行してください。

## コミット後の誤字チェック

コミットが成功したら、コミットメッセージを取得して誤字がないか確認してください。

```bash
git log -1 --format=%B
```

誤字があれば修正したメッセージを一時ファイルに書き出し、amendで上書きしてください。

```bash
git commit --amend --no-edit -F /tmp/coding-agent-work/COMMIT_EDITMSG
```

# 完了報告

コミットが完了したら、
コミットハッシュとメッセージを報告してください。
