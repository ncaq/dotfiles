# 作業ディレクトリ

`$XDG_RUNTIME_DIR/coding-agent-work/`はコーディングエージェントが自由に使える作業ディレクトリです。

基本的に環境変数`$XDG_RUNTIME_DIR`は`/run/user/<uid>`です。
典型的な`uid`は`1000`なので、
普通は`/run/user/1000`になっています。
それに`/coding-agent-work/`を付け加えたパスである、
`/run/user/1000/coding-agent-work/`が基本的には作業ディレクトリになります。

もちろん環境によっては動的に変わっています。

`$XDG_RUNTIME_DIR`が設定されていない環境では`/tmp/coding-agent-work/`にフォールバックします。

`claude/settings.json`の`permissions.additionalDirectories`に実際に使える作業ディレクトリが指定されています。

- 一時ファイルの出力先として使えます
- 承認なしでファイルの作成・編集・削除が可能です
- 自動的にクリーンアップされます
- ログアウト時や再起動時などにも自動的にクリーンアップされることがあります
