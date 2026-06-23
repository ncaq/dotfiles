# NixOS Installation with disko (Automatic)

This guide describes the automated installation process using disko.

## Prerequisites

- NixOS installation media booted
- Network and keyboard layout configured
- Terminal access

## Installation Steps

```bash
NEW_HOST=please-input-new-hostname
export NIX_CONFIG="experimental-features = flakes nix-command"
nix run 'nixpkgs#git' -- clone https://github.com/ncaq/dotfiles.git
cd dotfiles
sudo -E nix run '.#disko' -- --mode format,mount --flake ".#${NEW_HOST}"

# workaround nixos-install

sudo mkdir -p /mnt/build

df -h /
mount | grep -iE 'rw-store|overlay|/nix'
sudo mount -o remount,size=48G /nix/.rw-store

nix build "path:$PWD#nixosConfigurations.${NEW_HOST}.config.system.build.toplevel" \
  --out-link /mnt/build/toplevel \
  --extra-experimental-features "nix-command flakes"

TOPLEVEL=$(readlink -f /mnt/build/toplevel)
sudo nix copy --to /mnt "$TOPLEVEL" --no-check-sigs \
  --extra-experimental-features "nix-command flakes"

sudo nixos-install --system "$TOPLEVEL" --root /mnt --no-channel-copy
```

Please reboot after installation.

## Notes

- This method uses disko to automatically handle disk partitioning and formatting
- The disk configuration is defined in the flake configuration
- No manual partitioning is required
