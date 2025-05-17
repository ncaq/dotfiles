# dotfiles

My main configuration files.

It's managed by
[NixOS | Declarative builds and deployments](https://nixos.org/) and
[home-manager](https://github.com/nix-community/home-manager).

# Git Hooks

[./git-hooks/](./git-hooks/)

These are my Git global hooks.

# NixOS System Setup

Warning,
my default `$USERNAME` is `ncaq`.
I haven't tested with other usernames.
I write username by hardcode.
Maybe, if you want to use other username, you need to change code.

## Rebuild

``` zsh
sudo nixos-rebuild switch --flake ".#$(hostname)"
```

# Non NixOS System Setup

## Initial

``` zsh
nix run home-manager/master -- --flake '.#ncaq' init --switch .
```

## Rebuild

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
