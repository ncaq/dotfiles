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

- [NixOS with disko (Automatic)](./docs/install/nixos-disko.md) - Automated installation using disko for disk management
- [NixOS (Manual Partitioning)](./docs/install/nixos-manual.md) - Manual installation with custom partitioning, suitable for dual-boot

## Non NixOS

- [home-manager Standalone](./docs/install/home-manager.md) - Install home-manager only on non-NixOS systems

# Rebuild

```zsh
./install.sh
```

This script automatically detects your environment and runs the appropriate command:

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
I'm managing everything possible with home-manager.
I only use the NixOS configuration part when absolutely necessary.

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

The prompt for Chat LLM and Coding Agent.

## [lib/](./lib/)

The library files for Nix expressions.

## [nixos/](./nixos/)

NixOS configuration files.

## [pkg/](./pkg/)

Custom Nix packages.

# Separated dotfiles

- [ncaq/.emacs.d: My Emacs config](https://github.com/ncaq/.emacs.d)
- [ncaq/.xkeysnail: My xkeysnail config](https://github.com/ncaq/.xkeysnail)
- [ncaq/.xmonad](https://github.com/ncaq/.xmonad)
- [ncaq/.zsh.d](https://github.com/ncaq/.zsh.d)
- [ncaq/git-hooks: My Git global hooks](https://github.com/ncaq/git-hooks)
- [ncaq/infra.ncaq.net: Infrastructure as Code for ncaq.net](https://github.com/ncaq/infra.ncaq.net)
- [ncaq/keyhac-config](https://github.com/ncaq/keyhac-config)
- [ncaq/surfingkeys-config: My Surfingkeys config](https://github.com/ncaq/surfingkeys-config)
- [ncaq/winconf: My Windows configuration files](https://github.com/ncaq/winconf)
