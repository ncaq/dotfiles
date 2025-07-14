#!/usr/bin/env bash
set -euo pipefail

if [ -f /etc/NIXOS ]; then
  sudo nixos-rebuild switch --flake ".#$(hostname)"
else
  home-manager --flake ".#${USER}" switch
fi
