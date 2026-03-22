#!/usr/bin/env bash
set -euo pipefail

# gitやjqがPATHにない場合PATHに追加して再実行。
# Nix-on-Droidの初期環境などではインストールされていないため必要。
missing_packages=()
command -v git >/dev/null 2>&1 || missing_packages+=('nixpkgs#git')
command -v jq >/dev/null 2>&1 || missing_packages+=('nixpkgs#jq')
if [ ${#missing_packages[@]} -gt 0 ]; then
  exec nix shell "${missing_packages[@]}" --command "$0" "$@"
fi

# `stage_last_commit`で利用するファイルをクリーンアップすることを試みます。
# 失敗しても無害なファイルが残るだけなため、
# エラーは無視します。
cleanup_last_commit() {
  git reset -- last-commit.json 2>/dev/null || true
  if command -v trash >/dev/null 2>&1; then
    trash last-commit.json 2>/dev/null || true
  else
    rm last-commit.json 2>/dev/null || true
  fi
}

# 最新コミットの情報をlast-commit.jsonに保存してstagingします。
# flakeはstagingされたファイルのみをソースに含めるため、
# 一時的にgit addで注入してrebuild後にunstageします。
# last-commit.jsonのstagingで必ずdirtyになるため、注入前に本来のdirty状態を記録します。
stage_last_commit() {
  local subject branch dirty
  subject=$(git log -1 --format=%s)
  branch=$(git rev-parse --abbrev-ref HEAD)
  if git diff --quiet && git diff --cached --quiet; then
    dirty=false
  else
    dirty=true
  fi
  jq -n \
    --arg subject "$subject" \
    --argjson dirty "$dirty" \
    --arg branch "$branch" \
    '{subject: $subject, dirty: $dirty, branch: $branch}' \
    >last-commit.json
  git add -f last-commit.json
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
