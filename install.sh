#!/usr/bin/env bash
set -euo pipefail

# gitがPATHにない場合gitをPATHに追加して再実行。
# Nix-on-Droidの初期環境などではgitがインストールされていないため必要。
if ! command -v git &>/dev/null; then
  # gitがないとflakeの読み込みも出来ないのでnixpkgsの生の使用はやむを得ない。
  exec nix shell 'nixpkgs#git' --command "$0" "$@"
fi

# `stage_last_commit`で利用するファイルをクリーンアップすることを試みます。
# 失敗しても無害なファイルが残るだけなため、
# エラーは無視します。
cleanup_last_commit() {
  git reset -- last-commit 2>/dev/null || true
  if command -v trash >/dev/null 2>&1; then
    trash last-commit 2>/dev/null || true
  else
    rm last-commit 2>/dev/null || true
  fi
}

# 最新コミットのsubjectとdirty状態をlast-commitファイルに保存してstagingします。
# flakeはstagingされたファイルのみをソースに含めるため、
# 一時的にgit addで注入してrebuild後にunstageします。
# last-commitのstagingで必ずdirtyになるため、注入前に本来のdirty状態を記録します。
stage_last_commit() {
  git log -1 --format=%s >last-commit
  if git diff --quiet && git diff --cached --quiet; then
    echo "clean" >>last-commit
  else
    echo "dirty" >>last-commit
  fi
  git add -f last-commit
  trap cleanup_last_commit EXIT
}

if [ -f /etc/NIXOS ]; then
  stage_last_commit
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
