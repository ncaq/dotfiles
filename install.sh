#!/usr/bin/env bash
set -euo pipefail

# 設定を適用する処理の本体は`pkgs/dotfiles-install`です。
# ここはそれをこのリポジトリのflakeからビルドして起動するだけの入口です。

# どこから呼ばれてもこのリポジトリのflakeを見ます。
cd "$(dirname "$0")"

# gitが入っているか。
if command -v git >/dev/null 2>&1; then
  # gitが入っている場合はそのまま実行します。
  exec nix run '.#dotfiles-install' -- "$@"
else
  # 想定対象環境のNix-on-Droidの初期環境などにはgitが無く、
  # そこのNix 2.18.4はgitリポジトリのflakeを読むのに`git`コマンドを呼びます。
  # 本体をビルドする前の話なので、本体の依存関係ではなくここでgitを足します。
  # 上流が初期環境のNixをgitを呼ばない版に上げたら、この分岐は消せます。
  exec nix shell 'nixpkgs#git' --command nix run '.#dotfiles-install' -- "$@"
fi
