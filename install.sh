#!/usr/bin/env bash
set -euo pipefail

# gitがPATHにない場合gitをPATHに追加して再実行。
# Nix-on-Droidの初期環境などではgitがインストールされていないため必要。
if ! command -v git &>/dev/null; then
  # gitがないとflakeの読み込みも出来ないのでnixpkgsの生の使用はやむを得ない。
  exec nix shell 'nixpkgs#git' --command "$0" "$@"
fi

if [ -f /etc/NIXOS ]; then
  sudo nixos-rebuild switch --flake ".#$(hostname)"
elif [ -n "${TERMUX_VERSION:-}" ]; then
  nix-on-droid switch --flake "."
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
