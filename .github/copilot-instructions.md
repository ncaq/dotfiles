# For LLM Instructions

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
