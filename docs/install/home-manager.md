# home-manager Standalone Installation

This guide describes how to install home-manager standalone on non-NixOS systems.

## Prerequisites

- Nix package manager installed on your system
- Git installed

## Installation Steps

```zsh
git clone https://github.com/ncaq/dotfiles.git
cd dotfiles
nix run '.#home-manager' -- --flake ".#${USER}" init --switch .
```

## Notes

- This method only uses home-manager without NixOS
- Suitable for managing user environment on non-NixOS systems
- Does not require root privileges for most operations
