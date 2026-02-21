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

# home-manager

## Termux

### systemd

Termux環境ではsystemdが利用できません。
しかしサービスが有効にする設定を書いても、
インストール時には単にスキップされるだけでエラーにはなりません。

なのでTermux環境であることを検出して条件分岐をする必要は必須ではありません。

# 設計原則

## 宣言的ファースト

手動の設定手順は避けて、
なるべく宣言的な方法を使います。

命令的なソリューションを受け入れるのではなく、
宣言的な回避策を優先してください。

## 既存モジュール調査優先

カスタムアプローチを実装する前に、
既存のNixOSモジュールやnixpkgsのオプション、
コミュニティソリューションを調査してください。

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

# 利用環境

基本的にOSにはNixOSの最新安定版を使っています。
もしくは他のOSの上にNixパッケージマネージャを使っています。

`$HOST`変数を見れば`flake.nix`で作っているどの環境でインストールされているか分かります。

# 使用する技術スタックやライブラリ

環境構築には[Nix Flakes](https://wiki.nixos.org/wiki/Flakes/ja)を利用しています。

# リポジトリ構成

`CLAUDE.md`は以下のように`.github/copilot-instructions.md`のシンボリックリンクになっています。

```console
CLAUDE.md -> .github/copilot-instructions.md
```

# インフラ構築

マシンの設定を超えるTerraformを使うような外部のインフラの設定は、
[infra.ncaq.net](https://github.com/ncaq/infra.ncaq.net)
リポジトリの方で管理しています。

# シークレット管理

シークレットはsops-nixで管理されています。
gpg鍵で暗号化されたyamlファイルが`secrets/`ディレクトリに格納されています。

設定ファイルは`.sops.yaml`です。

# ネットワーク

このリポジトリで管理している全てのホストはTailscaleに接続されておりtailnet内で通信が可能です。

# seminarサーバ

自宅サーバ`seminar`はNixOSで稼働しており、
このdotfilesリポジトリで管理されています。

## サービス

ローカルネットワーク向けに様々なサービスを公開しています。
Tailnetを通じるとインターネットからもアクセス可能です。

Cloudflare Tunnelでインターネットからアクセス可能なサービスを公開しています。

Tailscale Funnelでもインターネットからアクセス可能なサービスを公開しています。
Cloudflare Tunnelを使わずTailscale Funnelを使う場合がある理由は、
Cloudflare TunnelはHTTPリクエストに厳しいサイズ制限があるためです。

各種サービスは隔離が容易かつ隔離する意味のあるものは、
[NixOS Containers](https://wiki.nixos.org/wiki/NixOS_Containers)か、
[microvm.nix](https://github.com/microvm-nix/microvm.nix)で隔離しています。

## ストレージ

大容量データは`/mnt/noa`にbtrfs RAID1で格納されています。

## データベース

PostgreSQLがホスト上で稼働しています。
各コンテナはbindMountされたUnixソケット(`/run/postgresql`)経由でpeer認証でアクセスします。
