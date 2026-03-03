---
description: AIがコミットメッセージを生成し、$EDITORでユーザが修正してからコミットします
model: sonnet
disable-model-invocation: true
allowed-tools:
  - Bash($EDITOR:*)
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

差分の意味がわからない場合は、
他のソースコードを参照するなどして理解を深めてください。

## コミットメッセージのガイドラインの確認

プロジェクトルートに`.github/git-commit-instructions.md`が存在する場合はReadツールで読み込んでください。
存在しない場合はスキップしてください。

## 既存コミットスタイルの把握

```bash
git log --oneline -10
```

既存のコミットメッセージのスタイル(Conventional Commitsなど)を把握してください。

## コミットメッセージの生成

ステージ済みの差分を分析し、
適切なコミットメッセージを生成してください。

`.github/git-commit-instructions.md`があればそのガイドラインに従います。

丁寧語とですます調で書いてください。

1行目はタイトルで簡潔に変更の要約。
タイトルは68文字以内に収めることが推奨されます。

必要に応じて空行の後に本文を追加。
本文の行長は出来る限り120文字以内に収めてください。
URLなど改行できないものを挿入する場合は例外です。
改行位置は文の区切りや句読点の後など、
自然な場所を選んでください。

GitHub向けのissueに関連付けるキーワードは`close`などの原形を使ってください。

## 一時ファイルへの書き出し

生成したコミットメッセージをWriteツールで以下のパスに書き出してください。

```
/tmp/coding-agent-work/COMMIT_EDITMSG
```

## ユーザによるコミットメッセージの編集

以下のコマンドでユーザにコミットメッセージを編集してもらいます。
タイムアウトは最大の600秒(10分)に設定してください。

```bash
$EDITOR /tmp/coding-agent-work/COMMIT_EDITMSG
```

## コミットの実行

以下のコマンドでコミットを実行してください。

```bash
git commit -F /tmp/coding-agent-work/COMMIT_EDITMSG
```

## commit-msgフック失敗時の対応

commit-msgフックが失敗した場合、
プロジェクト固有のコミットメッセージ規約とグローバルなgit-hookが衝突していることが原因であれば`--no-verify`で再試行してください。

```bash
git commit --no-verify -F /tmp/coding-agent-work/COMMIT_EDITMSG
```

単純に書き方が間違っている場合は、
コミットメッセージを生成することからやり直してください。

## コミット後の誤字チェック

コミットが成功したら、
コミットメッセージを取得して誤字がないか確認してください。

```bash
git log -1 --format=%B
```

誤字があれば修正したメッセージを一時ファイルに書き出し、
amendで上書きしてください。
初回コミットで`--no-verify`を使った場合はamendでも同様に指定してください。

```bash
git commit --amend -F /tmp/coding-agent-work/COMMIT_EDITMSG
```

# 完了報告

コミットが完了したら、
コミットハッシュとメッセージを報告してください。
