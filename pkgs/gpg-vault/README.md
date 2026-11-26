# gpg-vault

GPGの秘密鍵を通常ユーザから隔離する仕組みです。

コーディングエージェントなどが通常ユーザの権限で動いていても、
秘密鍵がうっかり外へ出ないようにします。
防ぐのは以下のミスです。

- ディレクトリを一括でアップロードして、秘密鍵のファイルが混ざる
- `gpg --export-secret-keys`などで秘密鍵をエクスポートする

厳密なアクセス制御ではありません。
通常ユーザは署名と復号とSSH認証を引き続き頼めます。
sudoを使えば制限の外へ出られます。
悪意は防げません。

## 仕組み

GnuPGは設計上、
gpgクライアントは秘密鍵のファイルを直接読まず、
秘密鍵を使う操作は全てgpg-agentへソケット経由で委譲します。
この性質を使って、
秘密鍵の実体とgpg-agentを専用のgpg-vaultユーザへ移して、
通常ユーザにはソケットだけを公開します。

- 秘密鍵の実体: `/var/lib/gpg-vault/.gnupg/private-keys-v1.d/`。gpg-vaultユーザの所有でmode 700
- gpg-agent: `gpg-vault-agent.service`がgpg-vaultユーザで動かす
- ソケット: `/run/gpg-vault/`に置く
- 通常ユーザの`~/.gnupg`: 公開鍵リングと設定だけで、秘密鍵は置かない

通常ユーザの側ではgpg-agentを起動しません。
gpgが探す`$XDG_RUNTIME_DIR/gnupg/`のソケットを、
vaultのソケットへのシンボリックリンクにしています。

## ソケット

agentは3つのソケットを`/run/gpg-vault/`に作ります。

| ソケット            | 繋げるユーザ          | できること                     |
| ------------------- | --------------------- | ------------------------------ |
| `S.gpg-agent`       | gpg-vaultユーザとroot | agentの全てのコマンド          |
| `S.gpg-agent.extra` | gpg-vaultグループ     | 署名と復号などの制限された操作 |
| `S.gpg-agent.ssh`   | gpg-vaultグループ     | ssh-agentのプロトコルでの認証  |

通常ユーザのgpgが普通のソケットとして探す`$XDG_RUNTIME_DIR/gnupg/S.gpg-agent`の先は、
`S.gpg-agent.extra`です。
gpgから見ると、
普通にagentへ繋いだつもりで制限付きのソケットへ繋がります。

`S.gpg-agent.extra`は、
GnuPGがリモートのマシンへagentを転送するために用意している制限付きのソケットです。
繋いできた相手を信用しない前提で、
agentが危険なコマンドを`Forbidden`で拒否します。
何を拒否するかはGnuPGのマニュアルに一覧が無く、
`agent/command.c`の`ctrl->restricted`を見ている箇所が根拠です。

## 通常ユーザからできることとできないこと

できること:

- 署名
- 復号
- SSH認証
- 公開鍵のインポートや一覧のような、秘密鍵を使わない操作

agentに拒否されること:

- 秘密鍵のエクスポート
- 秘密鍵のインポート
- 鍵の生成と削除
- パスフレーズの変更
- `--pinentry-mode loopback`への切り替え
- agentの終了と再読み込み

拒否されることは、
次の節の通りgpg-vaultユーザとして行います。

### `quiet`を設定している理由

制限付きのソケットに繋いだgpgは、
`gpg --list-secret-keys`や署名のたびに以下の警告を出します。

```console
gpg: problem with fast path key listing: Forbidden - ignored
```

gpgは秘密鍵の一覧を一度に取る近道(`HAVEKEY --list`)を最初に試しますが、
制限付きのソケットではagentがこれを必ず拒否します。
鍵ごとの問い合わせに切り替わるだけで、
動作に問題はありません。

常に出る警告は邪魔なので、
`home-module.nix`が通常ユーザの`gpg.conf`に`quiet`を設定して止めています。
gpgがこの警告を出さない条件は`quiet`だけです。
鍵ファイルの`Remote-list: true`は`KEYINFO --list`に効くもので、
この警告には効きません。

`quiet`はこの警告だけでなく、
gpgの情報メッセージ全般を減らします。
エラーと、署名の検証結果のような本筋の出力は残ります。
gpg-vaultユーザとして動かすgpgには設定していないので、
そちらでは普段通りのメッセージが出ます。

## 秘密鍵を管理する操作

秘密鍵のインポートのような管理の操作は、
gpg-vaultユーザとしてgpgを動かして、
全てのコマンドを受け付けるソケットへ繋いで行います。

```zsh
sudo -u gpg-vault env GNUPGHOME=/var/lib/gpg-vault/.gnupg gpg --list-secret-keys
```

gpg-vaultユーザは通常ユーザのファイルを読めないことが多いので、
ファイルは標準入力で渡して、
出力は標準出力で受け取ります。
リダイレクトでファイルを開くのは通常ユーザのシェルです。

秘密鍵のインポート:

```zsh
sudo -u gpg-vault env GNUPGHOME=/var/lib/gpg-vault/.gnupg \
  gpg --pinentry-mode loopback --import < subkeys-secret.asc
```

パスフレーズ付きの鍵をインポートするとagentがパスフレーズを求めるので、
後で書く`--pinentry-mode loopback`を付けています。

秘密鍵のエクスポート:

```zsh
sudo -u gpg-vault env GNUPGHOME=/var/lib/gpg-vault/.gnupg \
  gpg --export-secret-subkeys --armor '<鍵ID>!' > subkeys-secret.asc
```

パスフレーズの入力が要る操作には`--pinentry-mode loopback`を付けます。
agentは画面も端末も持たないユーザで動いていて、
pinentryを出せないので、
gpg自身にパスフレーズを入力します。

```zsh
sudo -u gpg-vault env GNUPGHOME=/var/lib/gpg-vault/.gnupg \
  gpg --pinentry-mode loopback --edit-key '<ユーザID>'
```

## 構成するファイル

- `package.nix`: agentのGNUPGHOMEへ置く設定ファイル。ソケットの場所と名前もここが決める
- `module.nix`: gpg-vaultユーザと`gpg-vault-agent.service`を定義するNixOSモジュール
- `home-module.nix`: 通常ユーザのgpgとsshをvaultのソケットへ向けるhome-managerモジュール
- `nixos-test.nix`: 実際のユニットを動かして、ソケットの権限と制限を確かめるテスト
- `module.test.nix`: `module.nix`が入力に掛けている検査のテスト

有効にしているのは`nixos/core/gpg-vault.nix`と`home/core/gpg.nix`です。
どの鍵を使うかは`key/`が持っていて、
鍵の運用は`key/README.md`に書いています。

rootで動くsops-install-secretsは、
vaultのGNUPGHOMEを直接指して`S.gpg-agent`へ繋ぎます。
ブートの途中で復号するので、
`module.nix`の`clientUnits`に入れてagentを先に起動させています。
