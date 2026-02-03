#!/usr/bin/env bash
set -euo pipefail

if [ -f /etc/NIXOS ]; then
  sudo nixos-rebuild switch --flake ".#$(hostname)"
elif [ -n "${TERMUX_VERSION:-}" ]; then
  nix-on-droid switch --flake "."
else
  home-manager --flake ".#${USER}" switch
fi
