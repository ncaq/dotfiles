# 出力設定

## 言語

AIは人間に話すときは日本語を使ってください。

しかし既存のコードのコメントなどが日本語ではない場合は、
コメント等は既存の言語に合わせてください。

## 記号

ASCIIに対応する全角形(Fullwidth Forms)は使用禁止。

具体的には以下のような文字は右のように変換してください:

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

指定ディレクトリ内の`.nix`ファイルと`default.nix`を持つサブディレクトリを自動的に収集し、
NixOSモジュールやhome-managerモジュールの`imports`に渡せるパスのリストを返します。
`default.nix`は呼び出し元自身の再帰importを防ぐため除外されます。
`default.nix`を持たないサブディレクトリはモジュールではないので無視されます。
サブディレクトリの中身は走査しません(そのサブディレクトリの`default.nix`が自身で管理します)。

各ディレクトリの`default.nix`で以下のように使用します:

```nix
{ importDirModules, ... }:
{ imports = importDirModules ./.; }
```

これにより新しい`.nix`ファイルやモジュールディレクトリを追加するだけで自動的にimportされ、
`default.nix`の`imports`リストを手動で更新する必要がありません。
一貫性のため`default.nix`はなるべくこの形だけにして、
モジュールが他のモジュールを明示的にimportするのは避けます。

`importDirModules`は`flake.nix`で`specialArgs`/`extraSpecialArgs`経由で、
全モジュールに渡されています。

# home-manager

## Termux

### systemd

Termux環境ではsystemdが利用できません。
しかしサービスが有効にする設定を書いても、
インストール時には単にスキップされるだけでエラーにはなりません。

なのでTermux環境であることを検出して条件分岐をする必要は必須ではありません。

# 使用する技術スタックやライブラリ

環境構築には[Nix Flakes](https://wiki.nixos.org/wiki/Flakes/ja)を利用しています。

# 利用環境

基本的にOSにはNixOSの最新安定版を使っています。
もしくは他のOSの上にNixパッケージマネージャを使っています。

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

## stableを優先

`flake.nix`の`inputs`では、

```nix
nixpkgs.url = "github:NixOS/nixpkgs/nixos-xx.yy";
nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
```

のようにstableとunstableのチャンネルの両方を指定しています。

unstableも有効にしている理由はいくつかあります。

Claude Codeなどのコーディングエージェントはあまりにも更新が早く、
サーバも最新バージョンのクライアントを要求してくることがあります。

そのような最新版に近いバージョンを使わないことで多大な不便が生じるパッケージは、
例外的にunstableからインストールしたいです。

もう一つはstableにまだ入っていなかったり、
stableのバージョンが自分の求める機能を提供していないパッケージを使う場合です。

そのような理由がない限りは、
unstableではなくstableを優先してください。

## 並列度は全力にする

作業途中のジョブでは並列度をCPUコアを完全に使う設定にしましょう。

CPUはスケジューラが割り当てをするので、
取り合ってもあまり問題のないリソースだからです。
作業が高速になることを好みます。

ずっと起動しているデーモンを設定する場合は別の話で、
全体のリソースを考える必要があります。

## btrfs上では明示的な可逆圧縮は不要

btrfsのマウントディスクは全てファイルシステムレベルのzstd圧縮を有効にしているので、
途中でファイルをzstdなどで可逆圧縮するステップは不要です。

WSL2の環境でbtrfsじゃないとか、
ネットワークの外部に持ち出すなどの場合は必要になることがあるかもしれません。

非可逆圧縮は別の話です。

## センシティブではない情報はテレメトリに渡す

知識は自由であるべきなので、
利用するソフトウェアが既定で送るテレメトリはわざわざ無効化せず、
開発に貢献します。
積極的に有効化して回るわけではなく、
無効にするのもセンシティブな情報が含まれる場合だけです。

何をセンシティブとみなすかは`docs/telemetry-policy.md`に書いています。

## 補助プログラムの言語の選び方

設定だけでは書けない処理のために、
このリポジトリは`pkgs`などに自作の補助プログラムを持っています。
新しく書く時の言語は、
以下を上から順に当てはめて最初に合ったものにします。

- 問題を明らかに手っ取り早く解決できる優れたライブラリがあり、それをスムーズに使えるなら、その言語
- 非常に単純な処理ならシェルスクリプト
- レイテンシが重要ならRust
- 特に理由が無ければHaskell

ライブラリを理由に言語を選ぶのは、
そのライブラリが無いと自前で大きな実装を抱えることになる場合です。
ComfyUIのカスタムノードがPythonなのは、
ComfyUI自身がPythonのモジュールとしてノードを読み込むためです。
どの言語にもある程度のライブラリで済むなら、
この基準には当てはまりません。

シェルスクリプトにするのは、
秘密を復号して別のコマンドへ渡すラッパーのように、
外部コマンドを順に呼ぶだけの処理です。
以下のどれかに当てはまるなら、
単純とは言えないので他の言語にします。

- 分岐や状態の持ち回りが増えて、読んで追うのが難しい
- 信頼できない入力を解釈する
- 構造のあるデータを組み立てたり読んだりするのが処理の中心になる
- 振る舞いをテストで固定したい

Rustにするのは、
人の操作のたびに起動されるコマンドのように、
起動や応答の遅さがそのまま体感に出るものです。
常駐して数分おきに動くものや、
ビルドやサービスの起動時に一度だけ走るものは、
レイテンシが重要とは言えません。

Haskellで書く時は、
`pkgs/git-repo-subscribe`などの既存のパッケージと同じ構成に揃えます。
himariを使うcabalプロジェクトにして、
テストはsandwichで書きます。
外部コマンドの出力のような複雑な文字列のパースには、
手書きの分割や再帰ではなくmegaparsecを使います。

これは原則なので例外はあります。
基準と違う言語を選ぶ時は、
その理由をパッケージの`default.nix`の冒頭のコメントに書いてください。

# 重要コマンド

## フォーマット

nix fmtでフォーマットとリントを実行できます。

```console
nix fmt
```

[nix-tasuke](https://github.com/ncaq/konoka/tree/master/plugins/nix-tasuke)プラグインにより、
Claudeの応答完了時にStopフックで`nix fmt`が自動実行されます。
ファイルの差分が出ることがあります。

## 統合チェックは`./check.sh`を使う

統合チェックを実行する時は、
`nix-fast-build`を直接実行せずに、
リポジトリルートの`./check.sh`を実行してください。

```console
./check.sh
```

このスクリプトは今のマシンのシステムの`checks`だけを`nix-fast-build`で評価してビルドします。
`nix-fast-build`を直接実行すると全システムの`checks`が評価され、
`callCabal2nix`のようなIFDを含むパッケージが、
そのシステムを実行できないマシンでは評価に失敗します。

追加の引数はそのまま`nix-fast-build`へ渡されます。

## 設定の適用は`./install.sh`を使う

設定をシステムに適用する時は、
`nixos-rebuild`や`home-manager`を直接実行せずに、
リポジトリルートの`./install.sh`を実行してください。

```console
./install.sh
```

このスクリプトは実行環境を自動判別して適切な適用コマンドを呼び分けます。

- NixOS: `sudo nixos-rebuild switch --flake ".#$(hostname)"`
- Termux(nix-on-droid): `nix-on-droid switch --flake .`
- その他のLinux: アーキテクチャに応じた`home-manager switch`

単なるラッパーではなく、
NixOSでは適用前に最新コミットの情報を`last-commit.json`として一時的にstagingします。
この情報は`nixos/core/label.nix`がブートエントリのラベル生成に使うため、
`nixos-rebuild`を直接実行するとブートエントリからコミット情報が欠落します。

実行にあたって知っておくべきこと:

- NixOSではsudoを使いますがユーザ側によって解決されるので気にしなくても良いです
- 実行中は`last-commit.json`のstagingにより一時的にgitがdirty状態に見えますが、
  終了時に自動でクリーンアップされます

# リポジトリ構成

## ルートディレクトリ

### LLM向けのシンボリックリンク

様々なコーディングエージェント向けの`AGENTS.md`と、
Claude Code向けの`CLAUDE.md`は、
以下のように`.github/copilot-instructions.md`のシンボリックリンクになっています。

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

## `home/core/claude-code.nix`

home-managerの`programs.claude-code`モジュールで全ホスト共通の設定を宣言的に管理します。
プラグイン、権限、フックなどの主要な設定を管理します。

ビルド時にユーザの`~/.claude/settings.json`として展開されます。

また、`.claude/settings.json`で管理できないタイプの設定は、
home-managerによって生成されたラッパープログラムを通じて渡されます。

## `home/core/llm-skill.nix`

LLM向けのスキルに類するものを読み込みます。

## `.claude/settings.json`

このリポジトリ(dotfilesプロジェクト)固有の設定です。

dotfilesでclaude codeを起動している時はNix管理のグローバル設定とマージされます。

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

そのtailnetに参加している全てのデバイスは、
自分の所有しているデバイスであり、
信頼できるものです。

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
