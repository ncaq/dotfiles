# 作業にスキルやエージェントがマッチする場合は利用する

## commit

前提として勝手にコミットをすることは控えてください。

Gitにコミットする時は、
[commit:commit](https://github.com/ncaq/konoka/blob/master/plugins/commit/skills/commit/SKILL.md)
スキルを基本的に使用してください。

Gitコマンドを直接使ってコミットしないでください。

スキルを利用したほうが文脈を読み取って適切なコミットメッセージを生成できる可能性が高いです。

### 例外

多数のリポジトリに対して決まった内容をコミットすることを指示された場合など、
非対話的にコミットすることを求められている場合は、
スキルを使用しないで構いません。

rebase時など細かなコミットメッセージの編集が必要な場合で、
amendなどの高度なオプションを使うのを求められた時は、
スキルを使用しないで構いません。

## log-analyzer

長大なファイルやコマンドの出力を解析する時は、
[log-analyzer:log-analyzer](https://github.com/ncaq/konoka/blob/master/plugins/log-analyzer/agents/log-analyzer.md)
エージェントを基本的に利用してください。

長大なファイルでも高速に結果が帰って来ることが期待できます。

## pr

前提として勝手にPRを作成することは控えてください。

Pull Requestを作成する時は、
[pr:pr](https://github.com/ncaq/konoka/blob/master/plugins/pr/skills/pr/SKILL.md)
スキルを基本的に使用してください。

GitHub MCPやGitHub CLIを直接使ってPRを作成しないでください。

スキルを利用したほうが文脈を読み取って適切なPRタイトルやPR説明を生成できる可能性が高いです。

### 例外

多数のリポジトリに対して決まった内容のPRを作るように指示された場合など、
非対話的にPRを作成することを求められている場合は、
スキルを使用しないで構いません。

## research

調べものをする時は、
[research:research](https://github.com/ncaq/konoka/blob/master/plugins/research/skills/research/SKILL.md)
スキルを基本的に使用してください。

高速に多数の情報を得ることが期待できます。

[research:survey](https://github.com/ncaq/konoka/blob/master/plugins/research/agents/survey.md)
エージェントはresearchスキルが内部的に使うためのエージェントなので、
直接呼び出さないでください。
