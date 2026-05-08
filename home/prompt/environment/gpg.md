# 電子署名と暗号

## GPGを主に以下の用途で使用しています

- メールへの署名
- Gitのコミットへの署名
- ファイルを暗号化してコミットに含める

などの用途にGPGを使っています。

## 公開鍵情報

公開鍵の情報は現在は以下の通りです。

```
❯ gpg --list-public-keys
/home/ncaq/.gnupg/pubring.kbx
-----------------------------
pub   ed25519/0x42248C7D0FB73D57 2026-01-05 [C] [有効期限: 2031-01-04]
   フィンガープリント = 7DDE 3BC4 05DC 58D9 4BF6  61D3 4224 8C7D 0FB7 3D57
uid                   [  究極  ] ncaq <ncaq@ncaq.net>
sub   cv25519/0xC65B759E5D5B3E95 2026-01-05 [E] [有効期限: 2031-01-04]
sub   ed25519/0xACA66AB679E75544 2026-01-22 [SA] [有効期限: 2031-01-21]
```

主鍵はオフラインの隔離されたストレージに保存されています。

詳細な管理方法は、
[dotfiles/key/README.md at master · ncaq/dotfiles](https://github.com/ncaq/dotfiles/blob/master/key/README.md)
に載っています。

## ソフトウェア使用

YubiKeyなどのハードウェアモジュールはGPGには使っていません。

どうせYubiKey Bioのような指紋認証対応のものはGPGに対応していないので、
それならば純粋にソフトウェアのGPGを使ってもセキュリティの強度はあまり変わらないと判断しているからです。
