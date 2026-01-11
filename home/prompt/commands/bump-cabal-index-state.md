---
description: cabalのindex-stateを最新に更新
allowed-tools:
  - Bash(cabal build:*)
  - Bash(cabal test:*)
  - Bash(cabal update:*)
  - Bash(nix flake check:*)
  - Bash(nix flake update:*)
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
出力例:

```console
Downloading the latest package list from hackage.haskell.org
Package list of hackage.haskell.org is up to date.
The index-state is set to 2026-01-11T09:48:01Z.
```

### index-stateの更新

通常は`cabal.project`ファイルに書かれている`index-state`を更新します。
フォーマット: `index-state: YYYY-MM-DDTHH:MM:SSZ`

もしここに書いていない場合、
`flake.nix`などに書かれている場合もあります。
探して更新してください。

### 動作確認

```bash
nix flake check
```

haskell.nixは最新の`index-state`への対応に遅れがある場合があるため、最新の`index-state`を使用するとエラーになる場合があります。
エラーメッセージに現在認識している最新の`index-state`が表示されます。

例:

```
> Error: [Cabal-7159]
> Latest known index-state for 'hackage.haskell.org' (2026-01-05T23:03:18Z) is older than the requested index-state (2026-01-11T18:45:48Z).
> Run 'cabal update' or set the index-state to a value at or before 2026-01-05T23:03:18Z.
```

このエラーが出た場合は、
エラーメッセージに記載されている最新の値を使用してください。

## haskell.nixを使用していない場合

### cabal updateの実行

```bash
cabal update
```

### index-stateの更新

cabal updateの出力から最新のタイムスタンプを取得し、
通常は`cabal.project`に書かれている`index-state`を更新します。

### 動作確認

プロジェクトのビルドシステムに応じて動作確認を行います。

Nixを使用している場合は`nix flake check`を実行してください。

Nixを使用していない場合は`cabal build`や`cabal test`などでビルド確認を行うか、
ユーザに動作確認が出来なかったことを報告してください。

# 完了報告

更新が完了したら以下を報告してください:

- 動作確認が成功したか
- 更新前の`index-state`
- 更新後の`index-state`
- haskell.nixを使用している場合、cabalの最新`index-state`とhaskell.nixが認識している最新`index-state`の差異
