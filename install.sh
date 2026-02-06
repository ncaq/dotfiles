#!/usr/bin/env bash
set -euo pipefail

if [ -f /etc/NIXOS ]; then
  sudo nixos-rebuild switch --flake ".#$(hostname)"
else
  case $(uname -m) in
  x86_64)
    home-manager --flake ".#x86_64-linux" -b "hm-bak" switch
    ;;
  aarch64)
    home-manager --flake ".#aarch64-linux" -b "hm-bak" switch
    ;;
  *)
    echo "未対応のプラットフォーム: $(uname -s)-$(uname -m)"
    exit 1
    ;;
  esac
fi
