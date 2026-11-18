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

## モジュールは置くだけで読み込まれる

各ディレクトリの`default.nix`は以下の形で、
同じディレクトリの`.nix`ファイルと、
`default.nix`を持つサブディレクトリを全て読み込みます。

```nix
{ importDirModules, ... }:
{ imports = importDirModules ./.; }
```

新しいモジュールはファイルを置くだけで有効になります。
一貫性のため`default.nix`はなるべくこの形だけにして、
モジュールが他のモジュールを明示的にimportするのは避けます。

何が除外されるかなどの詳しい動作は`lib/import-dir-modules.nix`に書いています。

# home-manager

## Termux

### systemd

Termux環境ではsystemdが利用できません。
しかしサービスを有効にする設定を書いても、
インストール時には単にスキップされるだけでエラーにはなりません。

なのでTermux環境であることを検出して条件分岐をすることは必須ではありません。

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
宣言的なワークアラウンドを優先してください。

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

## IPv6を基本にする

自分で構成するものは全てIPv6で動くようにして、
アドレスを指定する時はIPv6を使います。
IPv4はIPv4でしか届かない相手と繋がる時のレガシ対応に限ります。

詳しい方針は`docs/ip-version-policy.md`に書いています。

## SSDは空き容量を保って使う

SSDの上のファイルシステムは容量の10%以上を必ず空けておき、
普段は15%以上空いている状態を保ちます。
自動で容量を増やしていくものには、
自動で空きを取り戻す仕組みを組にします。

詳しい方針は`docs/ssd-policy.md`に書いています。

## 補助プログラムの言語の選び方

`pkgs`などに自作の補助プログラムを新しく書く時の言語は、
以下を上から順に当てはめて最初に合ったものにします。

- 問題を明らかに手っ取り早く解決できる優れたライブラリがあり、それをスムーズに使えるなら、その言語
- 非常に単純な処理ならシェルスクリプト
- レイテンシが重要ならRust
- 特に理由が無ければHaskell

それぞれの基準の詳しい意味は`docs/helper-program-language-policy.md`に書いています。

# 重要コマンド

## フォーマット

`nix fmt`でフォーマットとリントを実行できます。

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

既定で処理するのは、
ホストとhome-managerの構成を評価するだけに留めた軽いものです。
手元でCIと同じものを確かめたい時だけ、
構成のビルドとホストのブートテストまで含めて実行してください。

```console
CHECK_OUTPUT=ciJobs ./check.sh
```

直接実行してはいけない理由と引数の意味は`check.sh`のコメントに書いています。

## 設定の適用は`./install.sh`を使う

設定をシステムに適用する時は、
`nixos-rebuild`や`home-manager`を直接実行せずに、
リポジトリルートの`./install.sh`を実行してください。

```console
./install.sh
```

処理の本体は`pkgs/dotfiles-install`です。
実行環境を判別して適切な適用コマンドを呼び分けて、
NixOSではブートエントリのラベルに使う最新コミットの情報を`last-commit.json`として一時的にstagingします。
適用の振る舞いを変える時は`install.sh`ではなく`pkgs/dotfiles-install`を編集してください。

実行にあたって知っておくべきこと:

- NixOSではsudoを使いますがユーザ側によって解決されるので気にしなくても良いです
- 実行中は`last-commit.json`のstagingにより一時的にgitがdirty状態に見えますが、
  正常に終わった時も、失敗した時やCtrl-Cで止めた時も、終了時に自動でクリーンアップされます
- SIGTERMやSIGHUPで止められた時はクリーンアップされず、`last-commit.json`がstagingされたまま残ります。
  その時は`git reset -- last-commit.json`で外してからファイルを消してください

# リポジトリ構成

ディレクトリごとの構成と決まりは、
それぞれのディレクトリの`README.md`に書いています。

- `home/README.md`: home-managerの設定
- `nixos/README.md`: NixOSのシステム設定と、自宅サーバのseminarの概要
- `pkgs/README.md`: 自作のパッケージ。置くだけで拾われる仕組みと、その制約
- `test/README.md`: Nixのテストの書き方と置き場所

個々のファイルの役割や理由は、
そのファイルの冒頭のコメントに書きます。
ここへ書き足す前に、
実装の近くに書けないかを考えてください。

## LLM向けのシンボリックリンク

様々なコーディングエージェント向けの`AGENTS.md`と、
Claude Code向けの`CLAUDE.md`は、
`.github/copilot-instructions.md`へのシンボリックリンクです。
編集するのは`.github/copilot-instructions.md`です。

## Claude Codeの設定

全ホストに共通の設定は`home/core/claude-code.nix`で宣言していて、
`~/.claude/settings.json`として展開されます。
`~/.claude/settings.json`を直接書き換えないでください。
`.claude/settings.json`はこのリポジトリに固有の設定です。

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

# コンテナとmicroVMのログ

[NixOS Containers](https://wiki.nixos.org/wiki/NixOS_Containers)や、
[microvm.nix](https://github.com/microvm-nix/microvm.nix)のmicroVMの中のサービスのログは、
ホストで`machine-log`を使って読みます。

```console
machine-log
machine-log forgejo --since=-1h
machine-log mcp-nixos -f
```

引数を付けないとマシンの一覧を出します。
マシン名より後ろの引数は`journalctl`へそのまま渡ります。
中のユニット名では絞り込めないので、
`--grep`で絞ります。

仕組みは`nixos/native-linux/machine-log.nix`に書いています。
