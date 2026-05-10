# dotfiles

My main configuration files.

It's managed by
[NixOS | Declarative builds and deployments](https://nixos.org/) and
[home-manager](https://github.com/nix-community/home-manager).

# Note

> [!NOTE]
> My default `${USER}` is `ncaq`.
> I haven't tested with other usernames.
> I have hard-coded the username.
> Maybe, if you want to use other username, you need to change code.

# Initial

Choose the installation method that fits your environment:

## NixOS

- [Install using disko for automated](./docs/install/nixos-disko.md)
- [Install using manual work with exist partitioning](./docs/install/nixos-manual.md)

## Non NixOS

- [Install using home-manager on non-NixOS system](./docs/install/home-manager.md)
- [Install using Nix-on-Droid on Android](./docs/install/nix-on-droid.md)

# Rebuild

```zsh
./install.sh
```

This script automatically detects your environment and runs the appropriate command.

# Format

```zsh
nix fmt
```

# Check

## Static

```zsh
nix flake check
```

# Policy

As a general approach,
I use prefer home-manager.
I use NixOS option when necessary or easy.

# Directory Structure

## [flake.nix](./flake.nix)

The entry point of the flake.

## [home/](./home/)

The home-manager configuration files.

`home/` contains the home-manager configuration files.

### [home/link.nix](./home/link.nix), [home/linked/](./home/linked/)

Create symbolic links from filepath.
`link.nix` is the program that creates them.
`linked/` contains the linked files.

### [home/package/](./home/package/)

To install packages.

### [home/prompt/](./home/prompt/)

The prompt for Chat LLM and Coding Agent by direct.

## [lib/](./lib/)

The library files for Nix expressions.

## [nixos/](./nixos/)

NixOS configuration files.

## [pkgs/](./pkgs/)

Custom Nix packages.

# Related external config repo

- [ncaq/.emacs.d: My Emacs config](https://github.com/ncaq/.emacs.d)
- [ncaq/.xkeysnail: My xkeysnail config](https://github.com/ncaq/.xkeysnail)
- [ncaq/.xmonad](https://github.com/ncaq/.xmonad)
- [ncaq/.zsh.d](https://github.com/ncaq/.zsh.d)
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
