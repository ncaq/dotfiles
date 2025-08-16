# For LLM Instructions

## 出力設定

日本語で応答してください。
しかしコードのコメントなどは元の言語のままにしてください。

全角記号より半角記号を優先して使ってください。
特に全角括弧は禁止。

## 利用環境

基本的にOSにはNixOSの最新安定版を使っています。
もしくは他のOSの上にNixパッケージマネージャを使っています。

`$HOST`変数を見れば`flake.nix`で作っているどの環境でインストールされているか分かります。

## 重要コマンド

### フォーマット

基本的にファイルはツールで自動フォーマットしています。

#### nix fmt

[treefmt-nix](https://github.com/numtide/treefmt-nix)が対応しているファイルは以下のコマンドでフォーマット出来ます。

```console
nix fmt
```

### 統合チェック

以下のnixコマンドで、プロジェクト全体のフォーマットチェック・ビルド・テストが行えます。

```console
nix flake check
```

## 使用する技術スタックやライブラリ

環境構築には[Nix Flakes](https://wiki.nixos.org/wiki/Flakes/ja)を利用しています。
