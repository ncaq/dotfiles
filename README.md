# dotfiles

私のメインの設定ファイルです。

[NixOS | Declarative builds and deployments](https://nixos.org/)と、
[home-manager](https://github.com/nix-community/home-manager)で管理しています。

# 注意

> [!NOTE]
> 既定の`${USER}`は`ncaq`です。
> 他のユーザ名では試していません。
> ユーザ名はハードコードしています。
> 他のユーザ名で使うには、おそらくコードの変更が必要です。

# 初回のインストール

環境に合ったインストール方法を選んでください。

## NixOS

- [diskoを使ったインストール(自動)](./docs/install/nixos-disko.md)
- [既存のパーティションを残す手動のインストール](./docs/install/nixos-manual.md)

## NixOS以外

- [NixOS以外のシステムへhome-managerでインストール](./docs/install/home-manager.md)
- [AndroidへNix-on-Droidでインストール](./docs/install/nix-on-droid.md)

# 設定の適用

```zsh
./install.sh
```

このスクリプトは実行環境を自動で判別して、
適切なコマンドを実行します。

# フォーマット

```zsh
nix fmt
```

# チェック

```zsh
./check.sh
```

# 方針

基本的にはhome-managerを優先します。
NixOSのオプションを使うのは、
その方が単純な場合か、
それしか手段が無い場合だけです。

# 関連する外部の設定リポジトリ

- [ncaq/.emacs.d: My Emacs config](https://github.com/ncaq/.emacs.d)
- [ncaq/.xmonad](https://github.com/ncaq/.xmonad)
- [ncaq/.zsh.d](https://github.com/ncaq/.zsh.d)
- [ncaq/blue-prompt: LLMにブルーアーカイブを扱わせる時に役に立つリポジトリ](https://github.com/ncaq/blue-prompt)
- [ncaq/firge-nix: firgeフォントをnixで利用するためのリポジトリ](https://github.com/ncaq/firge-nix)
- [ncaq/git-hooks: My Git global hooks](https://github.com/ncaq/git-hooks)
- [ncaq/infra.ncaq.net: Infrastructure as Code for ncaq.net](https://github.com/ncaq/infra.ncaq.net)
- [ncaq/keyhac-config](https://github.com/ncaq/keyhac-config)
- [ncaq/konoka: AI prompts, agents, and skills as loadable plugins.](https://github.com/ncaq/konoka)
- [ncaq/kyosei-action: GitHub Action for kyosei code review from konoka marketplace.](https://github.com/ncaq/kyosei-action)
- [ncaq/nix-composite-action: My Nix setup with cache and etc.](https://github.com/ncaq/nix-composite-action)
- [ncaq/nix-templates: Flake templates](https://github.com/ncaq/nix-templates)
- [ncaq/nlod: JLODを改良したMozc/Google日本語入力向けのDvorakローマ字テーブル](https://github.com/ncaq/nlod)
- [ncaq/pppset: pandoc-page-preset](https://github.com/ncaq/pppset)
- [ncaq/renovate-config: renovate global config](https://github.com/ncaq/renovate-config)
- [ncaq/surfingkeys-config: My Surfingkeys config](https://github.com/ncaq/surfingkeys-config)
- [ncaq/winconf: My Windows configuration files](https://github.com/ncaq/winconf)
- [ncaq/www.ncaq.net: ncaq website](https://github.com/ncaq/www.ncaq.net)
