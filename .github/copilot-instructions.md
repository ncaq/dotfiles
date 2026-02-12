# 出力設定

## 言語

AIは人間にテキストを出力するときは日本語で出力してください。
しかしコードのコメントなどが日本語ではない場合は元の言語のままにしてください。

## 記号

ASCIIに対応する全角形(Fullwidth Forms)は使用禁止。

具体的には以下のような文字:

- 全角括弧 `（）` → 半角 `()`
- 全角コロン `：` → 半角 `:`
- 全角カンマ `，` → 半角 `,`
- 全角数字 `０-９` → 半角 `0-9`

# 利用環境

基本的にOSにはNixOSの最新安定版を使っています。
もしくは他のOSの上にNixパッケージマネージャを使っています。

`$HOST`変数を見れば`flake.nix`で作っているどの環境でインストールされているか分かります。

# リポジトリ構成

`CLAUDE.md`は以下のように`.github/copilot-instructions.md`のシンボリックリンクになっています。

```console
CLAUDE.md -> .github/copilot-instructions.md
```

# 重要コマンド

## フォーマット

基本的にファイルはツールで自動フォーマットしています。

### nix fmt

[treefmt-nix](https://github.com/numtide/treefmt-nix)が対応しているファイルは以下のコマンドでフォーマット出来ます。

```console
nix fmt
```

Stopフックで`nix fmt`が自動実行されます。
ファイルの差分が出ることがあります。

## 統合チェック

以下のコマンドでプロジェクト全体のフォーマットチェックとNixOS/home-manager構成の評価チェックが行えます。

```console
nix-fast-build --no-nom
```

`nix-fast-build`は`nix-eval-jobs`を使って`checks`を並列評価・ビルドします。
`nix flake check`と比べて、NixOS構成の評価が並列化されるため高速です。

# 使用する技術スタックやライブラリ

環境構築には[Nix Flakes](https://wiki.nixos.org/wiki/Flakes/ja)を利用しています。

# Nix言語

## 命名規則

[nixpkgsの公式コーディング規約](https://github.com/NixOS/nixpkgs/blob/master/pkgs/README.md)

### ファイル名・ディレクトリ名

kebab-caseを使用します。

例: `all-packages.nix`, `claude-code.nix`

### 変数名・属性名

| 種類                   | スタイル       | 例                                                         |
| ---------------------- | -------------- | ---------------------------------------------------------- |
| 純粋な変数・設定値     | lowerCamelCase | `keyConfig`, `identityKey`, `baseProfile`                  |
| パッケージ・derivation | kebab-case     | `github-mcp-server-wrapper`, `trayscale-autostart-desktop` |

単純な変数はlowerCamelCaseを使用します。

パッケージやプログラムを示す変数は、
pnameと同様にkebab-caseを使用します。
2012年以降、
Nix言語では識別子にハイフンを使用できます。

### NixOSオプション

原則camelCaseを使用します。

例: `services.nginx.enableReload`, `prompt.chatAssistant`

例外:

- パッケージ名を参照する場合はkebab-case: `services.nix-serve`
- `nix.settings`など外部設定ファイルをマッピングするオプションは、その設定ファイルの命名規則に従う(nix.confはkebab-case)

## `writeShellApplication`

デフォルトの安全性と分かりやすさの点で、
基本的に`writeShellScript`などよりも、
`writeShellApplication`を優先的に使用します。
