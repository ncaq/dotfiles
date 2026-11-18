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
