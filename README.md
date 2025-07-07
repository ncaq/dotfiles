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

## NixOS

### Manual

Use install media.
Install NixOS.
Run dotfiles.

### Automatic

> [!NOTE]
> Please input `please-input-new-hostname`.

``` zsh
new_hostname=please-input-new-hostname
nix --extra-experimental-features 'flakes nix-command' run 'nixpkgs#git' -- clone https://github.com/ncaq/dotfiles.git
cd dotfiles
sudo nix --experimental-features 'flakes nix-command' run github:nix-community/disko/latest -- --flake ".#${new_hostname}"
```

Please reboot.

## Non NixOS(home-manager standalone)

``` zsh
nix run home-manager/release-25.05 -- --flake ".#${USER}" init --switch .
```

# Rebuild

## NixOS

``` zsh
sudo nixos-rebuild switch --flake ".#$(hostname)"
```

## Non NixOS(home-manager standalone)

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

## [home/](./home/)

The home-manager configuration files.

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
