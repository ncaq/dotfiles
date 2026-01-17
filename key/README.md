# GPG鍵の運用方法

## 鍵の構成

- 暗号鍵: 全端末で共通の副鍵を使用
- 署名鍵: 各端末ごとに個別の副鍵を使用
  - ついでに認証鍵も署名鍵に紐付けています

署名鍵を端末ごとに分けている理由は、
漏洩時にどの端末から流出したか特定しやすいため。

暗号鍵を共通にしている理由は、
データを送る側からすると暗号鍵が異なると、
どの暗号鍵に向けて暗号化すれば良いか分からなくなるため。

## 公開鍵の更新先

[ncaq-public-key.asc](./ncaq-public-key.asc) を更新した場合、
以下の場所にも反映が必要:

- [GitHub](https://github.com/settings/keys)
- [Keybase](https://keybase.io/): `keybase pgp update`
- [keys.openpgp.org](https://keys.openpgp.org/upload)
- [ncaq/ncaq.net: https://ncaq.net/](https://github.com/ncaq/ncaq.net)

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

## 新しい副鍵の追加手順

### 副鍵生成手順

主鍵のデータを隔離ストレージからマウント。

クリーンな`GNUPGHOME`を設定。

```zsh
export GNUPGHOME=$(mktemp -d)
```

gpg-agentを再起動。

```zsh
cat > "$GNUPGHOME/gpg-agent.conf" << EOF
pinentry-program $(which pinentry-qt)
EOF
gpgconf --kill gpg-agent
```

主鍵をimport。

```zsh
gpg --import master-secret-key.asc
```

副鍵を追加。

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

```zsh
gpg --export-secret-subkeys --armor <暗号副鍵のフィンガープリント>! <署名認証副鍵のフィンガープリント>! > subkeys-<副鍵の名前>.asc
```

公開鍵をエクスポート。

```zsh
gpg --export --armor 7DDE3BC405DC58D94BF661D342248C7D0FB73D57 > ~/dotfiles/key/ncaq-public-key.asc
```

更新した鍵データを全て隔離ストレージにコピーしてアップデート。
具体的な手順は隔離ストレージの運用方法に従ってください。

`GNUPGHOME`を元に戻します。

```zsh
unset GNUPGHOME
```

隔離ストレージをアンマウントして保存場所に戻します。

### 端末にコピー

新しい副鍵を使う端末にコピーしてimportします。

```zsh
gpg --import /path/to/subkeys-<副鍵の名前>.asc
```

パスフレーズを削除します。

```zsh
gpg --edit-key ncaq@ncaq.net
```

```
gpg> passwd
```

1. 現在のパスフレーズを入力
2. 新しいパスフレーズは空にして決定

```
gpg> save
```

```zsh
gpgconf --kill gpg-agent
echo "test" | gpg --sign --armor
```

### dotfiles更新

[ncaq-public-key.asc](./ncaq-public-key.asc)の内容と、
[default.nix](./default.nix)の`identity-keys`を更新してコミットして、
PRを作ってマージしてください。

その後`./install.sh`を実行して、
ネットワーク上の公開鍵を更新してください。
