# dotfiles

use [home-manager](https://github.com/nix-community/home-manager).

# Git Hooks

* [./git-hooks/](./git-hooks/): My git global hooks

# NixOS System Setup

## Update

``` zsh
sudo nixos-rebuild switch --flake ".#$(hostname)"
```

# Non NixOS System Setup

## Initial

``` zsh
nix run home-manager/master -- --flake '.#ncaq' init --switch .
```

## Update

``` zsh
home-manager --flake '.#ncaq' switch
```

# Separated dotfiles

* [ncaq/.emacs.d: My Emacs config](https://github.com/ncaq/.emacs.d)
* [ncaq/.percol.d](https://github.com/ncaq/.percol.d)
* [ncaq/.xkeysnail: My xkeysnail config](https://github.com/ncaq/.xkeysnail)
* [ncaq/.xmonad](https://github.com/ncaq/.xmonad)
* [ncaq/.zsh.d](https://github.com/ncaq/.zsh.d)
* [ncaq/keyhac-config](https://github.com/ncaq/keyhac-config)
* [ncaq/surfingkeys-config: My Surfingkeys config](https://github.com/ncaq/surfingkeys-config)
* [ncaq/winconf: My Windows configuration files](https://github.com/ncaq/winconf)
