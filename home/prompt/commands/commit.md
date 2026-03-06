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
  - Bash(mkdir:*)
  - Bash(trash:*)
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

### コミットメッセージのスタイル

プロジェクト固有のガイドラインと衝突するスタイルがある場合はそちらを優先してください。
以下はデフォルトのスタイルとして使用してください。

丁寧語とですます調で書いてください。

英単語と日本語が混在する場合は、
英単語の前後にスペースを入れないでください。
中国語の風習では普通スペースを入れますが、
日本語ではスペースを入れないのも一般的で、
私は基本的にスペースなしのスタイルを採用しています。

1行目はタイトルなので簡潔に変更の要約をしてください。
タイトルは68文字以内に収めることが推奨されます。

必要に応じて空行の後に本文を追加してください。

本文の行長はできる限り120文字以内に収めてください。
URLなど改行できないものを挿入する場合は例外です。
行長が100文字程度なのは普通の行長で全く問題ないです。
行長が120文字になっても問題はありません。

改行位置は句読点の後など、
自然な場所を選んでください。
不自然な場所で改行はしないでください。
改行位置が不自然になるぐらいなら文章を練りなおしてください。
日本語は英語と違い好きに改行して良い言語ではないので、
改行位置には十分注意してください。

コードのシンボル(関数名や変数名など)をメッセージに含める場合は、
Markdownのインラインコード記法であるバッククォートで囲んでください。

GitHub向けのissueに関連付けるキーワードは`close`などの原形を使ってください。

本文には変更の内容だけではなく、
なぜその変更が必要だったのか、
理由をなるべく書いてください。

## 一時ファイルへの書き出し

`repo-name`は今のリポジトリ名に置き換えてください。

まずディレクトリを作成します。

```bash
mkdir -p /tmp/coding-agent-work/repo-name/
```

生成したコミットメッセージをWriteツールで以下のパスに書き出してください。
`git commit --verbose`と同様にエディタで差分を確認できるようにするため、
コミットメッセージの後にシザーズライン(scissors line)と差分を付加します。

差分は前のステップで取得した`git diff --cached`の出力を使用してください。
`diff --git`で始まる形式である必要があるので、
フルの形式を使用してください。

ファイルの内容は以下の形式にしてください。

```
ここにコミットメッセージ

# ------------------------ >8 ------------------------
差分を入力
```

書き出し先:

```
/tmp/coding-agent-work/repo-name/COMMIT_EDITMSG
```

## ユーザによるコミットメッセージの編集

以下のコマンドでユーザにコミットメッセージを編集してもらいます。
タイムアウトは最大の600秒(10分)に設定してください。

```bash
$EDITOR /tmp/coding-agent-work/repo-name/COMMIT_EDITMSG
```

## コミットの実行

以下のコマンドでコミットを実行してください。

```bash
git commit --cleanup=scissors -F /tmp/coding-agent-work/repo-name/COMMIT_EDITMSG
```

## commit-msgフック失敗時の対応

commit-msgフックが失敗した場合、
プロジェクト固有のコミットメッセージ規約とグローバルなgitフックが衝突していることが原因であれば`--no-verify`で再試行してください。

```bash
git commit --no-verify --cleanup=scissors -F /tmp/coding-agent-work/repo-name/COMMIT_EDITMSG
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
git commit --amend --cleanup=scissors -F /tmp/coding-agent-work/repo-name/COMMIT_EDITMSG
```

## コミットファイルのクリーンアップ

コミットが完了したら一時ファイルを削除してください。

```bash
trash /tmp/coding-agent-work/repo-name/COMMIT_EDITMSG
```

# 完了報告

コミットが完了したら報告してください。
