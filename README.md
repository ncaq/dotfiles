# dotfiles

My main configuration files.

It's managed by
[NixOS | Declarative builds and deployments](https://nixos.org/) and
[home-manager](https://github.com/nix-community/home-manager).

# Setup

Warning,
my default `${USER}` is `ncaq`.
I haven't tested with other usernames.
I write username by hardcode.
Maybe, if you want to use other username, you need to change code.

## Initial

### NixOS

TODO: Add NixOS setup instructions

### Non NixOS(home-manager standalone)

``` zsh
nix run home-manager/master -- --flake ".#${USER}" init --switch .
```

## Rebuild

### NixOS

``` zsh
sudo nixos-rebuild switch --flake ".#$(hostname)"
```

### Non NixOS(home-manager standalone)

``` zsh
home-manager --flake ".#${USER}" switch
```

# Format

``` zsh
nix fmt
```

# Check

## Static

``` zsh
nix flake check
```

## Dynamic

``` zsh
nix run github:nix-community/home-manager -- switch --flake ".#${USER}" -n -b backup
```

# Policy

As a general approach,
I'm managing everything possible with home-manager.
I only use the NixOS configuration part when absolutely necessary.

# Directory Structure

## [flake.nix](./flake.nix)

The entry point of the flake.

## [home.nix](./home.nix), [home/](./home/)

The home-manager configuration files.

`home.nix` is home-manager root file.
`home/` contains the home-manager configuration files.

### [home/link.nix](./home/link.nix), [home/linked/](./home/linked/)

Create symbolic links from filepath.
`link.nix` is the program that creates them.
`linked/` contains the linked files.

### [home/package/](./home/package/)

To install packages.

## [nixos/](./nixos/)

NixOS configuration files.

## [git-hooks/](./git-hooks/)

These are my Git global hooks.

It's semi standalone.
I might move it to a separate repository because it's unrelated to Nix.

# Separated dotfiles

* [ncaq/.emacs.d: My Emacs config](https://github.com/ncaq/.emacs.d)
* [ncaq/.percol.d](https://github.com/ncaq/.percol.d)
* [ncaq/.xkeysnail: My xkeysnail config](https://github.com/ncaq/.xkeysnail)
* [ncaq/.xmonad](https://github.com/ncaq/.xmonad)
* [ncaq/.zsh.d](https://github.com/ncaq/.zsh.d)
* [ncaq/keyhac-config](https://github.com/ncaq/keyhac-config)
* [ncaq/surfingkeys-config: My Surfingkeys config](https://github.com/ncaq/surfingkeys-config)
* [ncaq/winconf: My Windows configuration files](https://github.com/ncaq/winconf)
