---
description: cabalのindex-stateを最新に更新
allowed-tools:
  - Bash(cabal update:*)
  - Bash(nix flake check:*)
  - Bash(nix flake update:*)
  - Bash(nix fmt:*)
  - Edit
  - Glob
  - Grep
  - Read
  - Write
---

cabalプロジェクトの`index-state`を最新に更新します。

# 手順

## haskell.nixの使用確認

まずプロジェクトがhaskell.nixを使用しているか確認してください。
`flake.nix`または`flake.lock`に`haskell.nix`への参照があるか確認します。

## haskell.nixを使用している場合

### flake.lockの更新

先にflake.lockを最新に更新してコミットするコマンドを実行します。

```bash
nix flake update --commit-lock-file --option commit-lockfile-summary "build(deps): bump \`flake.lock\`"
```

### cabal updateの実行

```bash
cabal update
```

cabal updateの出力から最新の`index-state`タイムスタンプを取得します。
出力例: `Downloaded package list from haskell.org (timestamp: 2026-01-11T12:34:56Z)`

### index-stateの更新

`cabal.project`ファイルの`index-state`を更新します。
フォーマット: `index-state: YYYY-MM-DDTHH:MM:SSZ`

### 動作確認

```bash
nix flake check
```

haskell.nixは追随に遅れがあるため、最新の`index-state`を使用するとエラーになる場合があります。
エラーメッセージに現在認識している最新の`index-state`が表示されます。

例:

```
> Error: [Cabal-7159]
> Latest known index-state for 'hackage.haskell.org' (2026-01-05T23:03:18Z) is older than the requested index-state (2026-01-11T18:45:48Z).
> Run 'cabal update' or set the index-state to a value at or before 2026-01-05T23:03:18Z.
```

このエラーが出た場合は、
エラーメッセージに記載されている`Latest known index-state for 'hackage.haskell.org'`の値を使用してください。

## haskell.nixを使用していない場合

### cabal updateの実行

```bash
cabal update
```

### index-stateの更新

cabal updateの出力から最新のタイムスタンプを取得し、`cabal.project`の`index-state`を更新します。

### 動作確認

プロジェクトのビルドシステムに応じて動作確認を行います。
Nixを使用している場合は`nix flake check`を実行してください。

# 完了報告

更新が完了したら以下を報告してください:

- 更新前の`index-state`
- 更新後の`index-state`
- haskell.nixの使用有無
