# 出力設定

## 言語

AIは人間に話すときは日本語を使ってください。

しかし既存のコードのコメントなどが日本語ではない場合は、
コメント等は既存の言語に合わせてください。

## 記号

ASCIIに対応する全角形(Fullwidth Forms)は使用禁止。

具体的には以下のような文字:

- 全角括弧 `（）` → 半角 `()`
- 全角コロン `：` → 半角 `:`
- 全角カンマ `，` → 半角 `,`
- 全角数字 `０-９` → 半角 `0-9`

# Nix

## `importDirModules`関数

`lib/import-dir-modules.nix`で定義されているユーティリティ関数です。
型は`Path -> [Path]`で、
ディレクトリパスを受け取り、
モジュールパスのリストを返します。

指定ディレクトリ内の`.nix`ファイルを自動的に収集し、
NixOSモジュールやhome-managerモジュールの`imports`に渡せるパスのリストを返します。
`default.nix`は呼び出し元自身の再帰importを防ぐため除外されます。
サブディレクトリは走査しません(1階層のみ)。

各ディレクトリの`default.nix`で以下のように使用します:

```nix
{ importDirModules, ... }:
{ imports = importDirModules ./.; }
```

これにより新しい`.nix`ファイルを追加するだけで自動的にimportされ、
`default.nix`の`imports`リストを手動で更新する必要がありません。

サブディレクトリのモジュールが必要な場合は手動で追加します:

```nix
imports = importDirModules ./. ++ [ ./github-runner ];
```

`importDirModules`は`flake.nix`で`specialArgs`/`extraSpecialArgs`経由で全モジュールに渡されています。

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

nix fmtでフォーマットとリントを実行できます。

```console
nix fmt
```

[nix-tasuke](https://github.com/ncaq/konoka/tree/master/plugins/nix-tasuke)プラグインにより、
Claudeの応答完了時にStopフックで`nix fmt`が自動実行されます。
ファイルの差分が出ることがあります。

## 統合チェック

nix-fast-buildコマンドで統合チェックを実行できます。

```console
nix-fast-build --option eval-cache false --no-link --skip-cached --no-nom
```

# 利用環境

基本的にOSにはNixOSの最新安定版を使っています。
もしくは他のOSの上にNixパッケージマネージャを使っています。

`$HOST`変数を見れば`flake.nix`で作っているどの環境でインストールされているか分かります。

# 使用する技術スタックやライブラリ

環境構築には[Nix Flakes](https://wiki.nixos.org/wiki/Flakes/ja)を利用しています。

# リポジトリ構成

## ルートディレクトリ

### LLM向けのシンボリックリンク

Codex向けの`AGENTS.md`とClaude Code向けの`CLAUDE.md`は以下のように`.github/copilot-instructions.md`のシンボリックリンクになっています。

```console
AGENTS.md -> .github/copilot-instructions.md
CLAUDE.md -> .github/copilot-instructions.md
```

これにより各種LLM向けのドキュメントを一元管理しています。

## homeディレクトリ

home-managerの設定ディレクトリです。
`home/default.nix`がエントリポイントです。

- `core/`: 全環境で共通の設定
- `linked/`: シンボリックリンクで配置される設定ファイル
- `native-linux/`: ネイティブLinux環境(NixOSなど、WSLやTermuxではない環境)専用の設定
- `prompt/`: LLM向けのプロンプト設定
- `wsl/`: WSL2環境専用の設定

## nixosディレクトリ

NixOSのシステム設定ディレクトリです。
`nixos/configuration.nix`がエントリポイントで`core/`をimportします。
各ホストの設定(`host/`)が追加のモジュールを選択的にimportする構造です。

- `core/`: 全NixOSホスト共通の設定
- `desktop/`: 据え置きデスクトップPC固有の設定、ラップトップPCには適用されない
- `host/`: ホストごとの個別設定、各ホストがモジュールを組み合わせてimportする
- `laptop/`: ラップトップPC固有の設定、据え置きデスクトップPCには適用されない
- `native-linux/`: ネイティブLinux環境(WSLではない)のシステム設定
- `test/`: テスト用設定
- `wsl/`: WSL2環境専用のNixOS設定

# Claude Code設定

Claude Codeの設定は2箇所で管理されています。

## `home/core/claude-code.nix`

home-managerの`programs.claude-code`モジュールで全ホスト共通の設定を宣言的に管理します。
MCPサーバ、プラグイン、権限、フックなどの主要な設定はここで管理します。

ビルド時にユーザの`~/.claude/settings.json`として展開されます。

また、`.claude/settings.json`で管理できないタイプの設定は、
home-managerによって生成されたラッパープログラムを通じて渡されます。

## `.claude/settings.json`

このリポジトリ(dotfilesプロジェクト)固有の設定です。

dotfilesでclaude codeを起動している時はNix管理のグローバル設定とマージされます。

両方のファイルで同じ設定項目(例: `extraKnownMarketplaces`のプラグインバージョン)を管理している場合、
両方を同時に更新する必要があります。

一つに統一できないのはCIなどの都合上やむを得ないことです。

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

各種サービスは隔離が容易かつ隔離する意味のあるものは、
[NixOS Containers](https://wiki.nixos.org/wiki/NixOS_Containers)か、
[microvm.nix](https://github.com/microvm-nix/microvm.nix)で隔離しています。

## ストレージ

大容量データは`/mnt/noa`にbtrfs RAID1で格納されています。

## データベース

PostgreSQLがコンテナ上で稼働しています。
各クライアントはbindMountされたUnixソケット(`/run/postgresql`)経由でpeer認証でアクセスします。
