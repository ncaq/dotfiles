# GitHubへのアクセス方法

## 直接URLアクセスの問題点

GitHubのURLをWebFetchなどで直接取得することは避けてください。
以下の問題が発生します。

- プライベートリポジトリにはアクセスできない。
- HTMLページは構造化されておらずLLMには扱いにくい。
- レート制限に引っかかりやすい。

## 推奨されるアクセス方法

### GitHub MCP

GitHub MCPが利用可能な場合は、これを優先して使用してください。
`mcp__github__`で始まるツールが利用可能です。

主要なツール:

- `mcp__github__get_file_contents`: ファイル内容の取得
- `mcp__github__issue_read`: Issue情報の取得
- `mcp__github__pull_request_read`: Pull Request情報の取得
  - method=`get_status`でGitHub Actionsのビルド・チェック結果を確認可能
- `mcp__github__search_code`: コード検索
- `mcp__github__search_issues`: Issue検索
- `mcp__github__list_commits`: コミット一覧の取得

### GitHub CLI

MCPが使えない場合はGitHub CLI(`gh`)を使用してください。

推奨するコマンド例:

- `gh repo view owner/repo`: リポジトリ情報の表示
- `gh issue view 123 --repo owner/repo`: Issue情報の表示
- `gh pr view 456 --repo owner/repo`: Pull Request情報の表示
- `gh pr diff 456 --repo owner/repo`: Pull Requestの差分表示
- `gh release list --repo owner/repo`: リリース一覧の表示

#### GitHub Actions関連

- `gh run list --repo owner/repo`: ワークフロー実行一覧の表示
- `gh run view RUN_ID --repo owner/repo`: 特定の実行の詳細表示
- `gh run view RUN_ID --repo owner/repo --log`: 実行ログの表示
- `gh run view RUN_ID --repo owner/repo --log-failed`: 失敗したジョブのログのみ表示
- `gh workflow list --repo owner/repo`: ワークフロー一覧の表示

#### 非推奨

`gh api`コマンドは低レベルすぎるため非推奨です。
理由:

- 人間が承認時に何が実行されるか理解しにくい。
- 高レベルなサブコマンドで同じことができる場合が多い。
- エンドポイントの知識が必要になる。

代わりに`gh issue`, `gh pr`, `gh repo`などの専用サブコマンドを使用してください。
