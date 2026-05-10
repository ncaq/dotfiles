# NixOS Installation with disko (Automatic)

This guide describes the automated installation process using disko.

## Prerequisites

- NixOS installation media booted
- Network and keyboard layout configured
- Terminal access

## Installation Steps

```zsh
NEW_HOST=please-input-new-hostname
export NIX_CONFIG="experimental-features = flakes nix-command"
nix run 'nixpkgs#git' -- clone https://github.com/ncaq/dotfiles.git
cd dotfiles
sudo -E nix run '.#disko' -- --mode format,mount --flake ".#${NEW_HOST}"
sudo nixos-install --flake ".#${NEW_HOST}" --root /mnt
```

Please reboot after installation.

## Notes

- This method uses disko to automatically handle disk partitioning and formatting
- The disk configuration is defined in the flake configuration
- No manual partitioning is required
