---
description: 依存関係の更新の報告
allowed-tools:
  - Bash
  - Edit
  - Glob
  - Grep
  - Read
  - Skill
  - TodoWrite
  - WebFetch
  - WebSearch
  - Write
  - mcp__deepwiki
  - mcp__github__get_file_contents
  - mcp__github__issue_read
  - mcp__github__list_issues
  - mcp__github__list_pull_requests
  - mcp__github__pull_request_read
  - mcp__github__search_code
  - mcp__github__search_issues
  - mcp__github__search_pull_requests
  - mcp__github__search_repositories
---

依存関係の更新に対して、
その内容とプロジェクトへの影響を調査・報告します。

# 手順

## 変更されたものの確認

`git log`や`git diff`などを使って、
このPRもしくは注目すべきコミットでどの依存関係が更新されたかを特定します。

## リンターの実行

そのプロジェクトのリンターを実行して、
静的なコード解析を行い、
その時点で問題がないか確認します。

## 変更内容の調査

依存関係の更新内容について調査します。

リリースノートやchangelogを調査して、
変更内容を把握します。

## プロジェクトへの影響の評価

更新された依存関係が現在のプロジェクトに与える影響を評価します。

評価するために現在のコードベースを確認します。

## レポートの作成

変更内容とその影響をまとめたレポートを作成します。
作業ディレクトリにMarkdownファイルとして保存してください。

## レポートの表示

作成したレポートを表示してください。
