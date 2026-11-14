#!/usr/bin/env bash
set -euo pipefail

# どこから呼ばれてもこのリポジトリのflakeを見ます。
cd "$(dirname "$0")"

# 処理の本体は`pkgs/dotfiles-install`のHaskell実装です。
# ここはまだ何も入っていない環境からそれをビルドして切り替えるだけの入口です。
#
# gitがPATHに無い時だけ、`nix shell`でgitを足してから呼びます。
# Nix-on-Droidの初期環境にはgitがインストールされておらず、
# そこのNixはgitリポジトリのflakeを評価するのに`git`コマンドを呼ぶためです。
# 本体はgitを自分で持っているので、足すのは本体をビルドするまでのためです。
if command -v git >/dev/null 2>&1; then
  exec nix run '.#dotfiles-install' -- "$@"
else
  exec nix shell 'nixpkgs#git' --command nix run '.#dotfiles-install' -- "$@"
fi
