# home-manager単体でのインストール

NixOS以外のシステムへ、
home-managerを単体でインストールする手順です。

## 前提

- Nixパッケージマネージャがインストールされている
- Gitがインストールされている

## インストールの手順

```zsh
git clone https://github.com/ncaq/dotfiles.git
cd dotfiles
nix run '.#home-manager' -- --flake ".#x86_64-linux" -b "hm-bak" init --switch .
```

## 補足

- NixOSを使わずにhome-managerだけを使います
- NixOS以外のシステムでユーザの環境を管理するのに向いています
- ほとんどの操作にroot権限は要りません
