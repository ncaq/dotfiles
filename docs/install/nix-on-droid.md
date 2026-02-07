# Nix-on-Droid Installation

This guide describes how to install this dotfiles configuration on Android using Nix-on-Droid.

## Prerequisites

- Android device (aarch64 architecture)
- F-Droid installed on the device

## Installation Steps

### 1. Install Nix-on-Droid

Install Nix-on-Droid from the F-Droid repository.

[Nix-on-Droid | F-Droid](https://f-droid.org/ja/packages/com.termux.nix/)

### 2. Clone and Apply Configuration

After the initial Nix-on-Droid setup completes,
run the following commands in the Nix-on-Droid terminal.

```bash
cd ~
nix run 'nixpkgs#git' -- clone https://github.com/ncaq/dotfiles.git
cd dotfiles
./install.sh
```

### 3. Restart the App

After the switch completes, restart the Nix-on-Droid app completely to apply all changes.

## Updating

```zsh
cd ~/dotfiles
./install.sh
```

## Notes

- Timezone is explicitly set to Asia/Tokyo
