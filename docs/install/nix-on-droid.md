# Nix-on-Droidでのインストール

Nix-on-Droidを使って、
このdotfilesの設定をAndroidへインストールする手順です。

## 前提

- Androidの端末(aarch64)
- 端末にF-Droidがインストールされている

## インストールの手順

### Nix-on-Droidをインストールする

F-DroidのリポジトリからNix-on-Droidをインストールします。

[Nix-on-Droid | F-Droid](https://f-droid.org/packages/com.termux.nix/)

### ブートストラップのURLを書き換える

アプリを初めて起動すると、
ブートストラップのzipを置いているディレクトリのURLを聞かれます。
既定で入っている`https://nix-on-droid.unboiled.info/bootstrap-release-24.05`は使わずに、
以下へ書き換えます。

```text
https://nix-on-droid.unboiled.info/bootstrap
```

既定のブートストラップが同梱するprootは古く、
nixpkgs 26.05のglibcで作られたプログラムが端末を扱えないので、
このdotfilesの適用が`getting pseudoterminal attributes: Permission denied`で失敗します。

[Activation failed with nixos-unstable and 26.05 · Issue #495 · nix-community/nix-on-droid](https://github.com/nix-community/nix-on-droid/issues/495)

続いてflakeでセットアップするかを聞かれます。
どちらを選んでも後でこのdotfilesの設定に置き換わります。

### cloneして設定を適用する

Nix-on-Droidの初期設定が終わったら、
Nix-on-Droidのターミナルで以下のコマンドを実行します。

```bash
cd ~
nix run 'nixpkgs#git' -- clone https://github.com/ncaq/dotfiles.git
cd dotfiles
./install.sh
```

### アプリを再起動する

切り替えが終わったら、
全ての変更を反映するためにNix-on-Droidのアプリを完全に再起動します。

## 更新

```zsh
cd ~/dotfiles
./install.sh
```

## 補足

- タイムゾーンは明示的にAsia/Tokyoへ設定しています
- 実機ではディレクトリをソースにするパッケージをビルドできません。
  prootが`fchmodat2`を扱えず、ソースの展開で`cp`が失敗するためです。
  公式のキャッシュに無いものはCIの`build-nix-on-droid`がビルドしてキャッシュへ送るので、
  変更はCIが通ってから適用します。
  [`cp` fails with "No such file or directory" · Issue #550 · nix-community/nix-on-droid](https://github.com/nix-community/nix-on-droid/issues/550)
