# GPG鍵の運用方法

## 前提知識

公開鍵のフィンガープリント: `7DDE3BC405DC58D94BF661D342248C7D0FB73D57`

## 鍵の構成

- 暗号副鍵: 全端末で共通
- 署名副鍵: 全端末で共通(認証機能も付与)

全副鍵を共通にしている理由:

- 暗号鍵: データを送る側からするとどの暗号鍵に向けて暗号化すれば良いか分からなくなるため
- 署名鍵: 端末ごとに分けると管理が煩雑になり、実用上のメリットより運用コストが上回るため

## 副鍵はパスフレーズなし

以下の理由から副鍵のパスフレーズはセキュリティ向上にあまり寄与しないと判断しています:

1. 主鍵はUSBメモリに隔離済み: 物理的に保護されている
2. パスフレーズはパスワードマネージャに保存: 暗号化されているとは言え同じマシンにある
3. ラップトップはディスク暗号化済み: 物理アクセスへの防御がある

攻撃者が秘密鍵ファイルにアクセスできる状態なら、
同じマシンのパスワードマネージャやメモリ上のキャッシュにもアクセスできる可能性が高いです。

パスフレーズによるセキュリティはパスフレーズを脳内に記憶している前提のモデルであり、
パスワードマネージャからコピペする運用ではその前提が崩れます。
そして私が脳内に記憶できる程度のパスフレーズは脆弱です。
結果としてセキュリティ上の意味はほぼないのに手間だけ増える状態になってしまいます。

## 副鍵の更新手順

副鍵の有効期限が近づいた場合や、
新しい副鍵に更新する場合の手順です。

### 副鍵生成

主鍵が保存されているUSBメモリをマウントし、
`GNUPGHOME`を設定。

```zsh
export GNUPGHOME=/mnt/<USBメモリ>/.gnupg
gpgconf --kill gpg-agent
```

署名・認証副鍵を追加。

```zsh
gpg --quick-add-key 7DDE3BC405DC58D94BF661D342248C7D0FB73D57 ed25519 sign,auth 5y
```

鍵一覧を見て発行された副鍵を確認。
普通は末尾に追加されています。
副鍵のフィンガープリントをメモしておきます。

```zsh
gpg --list-keys --with-subkey-fingerprint --full-timestrings 7DDE3BC405DC58D94BF661D342248C7D0FB73D57
```

副鍵をエクスポート。
暗号副鍵と署名認証副鍵の両方を含めます。

```zsh
gpg --export-secret-subkeys --armor <暗号副鍵のフィンガープリント>! <署名認証副鍵のフィンガープリント>! > subkeys-secret.asc
```

公開鍵をエクスポート。

```zsh
gpg --export --armor 7DDE3BC405DC58D94BF661D342248C7D0FB73D57 > ~/dotfiles/key/ncaq-public-key.asc
```

`GNUPGHOME`を元に戻してUSBメモリをアンマウント。

```zsh
unset GNUPGHOME
gpgconf --kill gpg-agent
```

### 端末にimport

副鍵をimportします。

```zsh
gpg --import subkeys-secret.asc
```

パスフレーズを削除します。

```zsh
gpg --edit-key ncaq@ncaq.net
```

```console
gpg> passwd
```

1. 現在のパスフレーズを入力
2. 新しいパスフレーズは空にして決定

```console
gpg> save
```

動作確認。

```zsh
gpgconf --kill gpg-agent
echo "test" | gpg --sign --armor
```

### dotfiles更新

[ncaq-public-key.asc](./ncaq-public-key.asc)と、
[default.nix](./default.nix)の`identityKey`を更新して、
コミットしてPRを作ってマージしてください。

その後`./install.sh`を実行して、
端末の鍵を更新してください。

## 公開鍵の更新先

[ncaq-public-key.asc](./ncaq-public-key.asc)
を更新した場合、
公開鍵の更新が必要です。

dotfilesが展開されている端末では公開鍵は自動で更新されるので更新不要です。

以下のネットワークサービスには手動反映が必要です。

### [GitHub](https://github.com/settings/keys)

十分な権限をGitHub CLIに与えてください。
できない場合はWeb UIで手動更新してください。

```zsh
gh gpg-key list
gh gpg-key delete 42248C7D0FB73D57 --yes
gh gpg-key add ~/dotfiles/key/ncaq-public-key.asc --title ncaq-public-key.asc
```

### [Keybase](https://keybase.io/)

```zsh
keybase pgp update
```

### [keys.openpgp.org](https://keys.openpgp.org/upload)

```zsh
gpg --keyserver keys.openpgp.org --send-keys 7DDE3BC405DC58D94BF661D342248C7D0FB73D57
```

### [ncaq/ncaq.net: https://ncaq.net/](https://github.com/ncaq/ncaq.net)

dotfilesがマージされたあと、

```zsh
nix flake update --commit-lock-file --option commit-lockfile-summary "build(deps): bump \`flake.lock\`"
```

を実行してPRを作って、
マージしてGitHub Actionsによるデプロイをトリガーしてください。
