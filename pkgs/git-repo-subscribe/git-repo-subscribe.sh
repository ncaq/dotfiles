#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: git-repo-subscribe URL PATH FILTER" >&2
  exit 2
fi

url=$1
path=$2
filter=$3

if [ ! -e "$path" ]; then
  mkdir -p "$(dirname "$path")"
  git clone --filter="$filter" --single-branch -- "$url" "$path"
  exit 0
fi

if ! git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Warning: $path is not a Git worktree; skipping update." >&2
  exit 0
fi

worktree_root=$(git -C "$path" rev-parse --show-toplevel)
if [ "$(realpath -e "$path")" != "$(realpath -e "$worktree_root")" ]; then
  echo "Warning: $path is not the root of its Git worktree; skipping update." >&2
  exit 0
fi

if ! origin_url=$(git -C "$path" remote get-url origin 2>/dev/null); then
  echo "Warning: $path has no origin remote; skipping update." >&2
  exit 0
fi

if [ "$origin_url" != "$url" ]; then
  echo "Warning: origin URL of $path is $origin_url, expected $url; skipping update." >&2
  exit 0
fi

if [ -n "$(git -C "$path" status --porcelain=v1 --untracked-files=normal)" ]; then
  echo "Warning: $path has local changes; skipping update." >&2
  exit 0
fi

if ! current_branch=$(git -C "$path" symbolic-ref --quiet --short HEAD); then
  echo "Warning: $path has a detached HEAD; skipping update." >&2
  exit 0
fi

if ! remote_head=$(git ls-remote --symref -- "$url" HEAD); then
  echo "Warning: unable to query the default branch of $url; skipping update." >&2
  exit 0
fi

default_branch=
while IFS= read -r line; do
  if [[ $line =~ ^ref:\ refs/heads/(.+)[[:space:]]HEAD$ ]]; then
    default_branch=${BASH_REMATCH[1]}
    break
  fi
done <<<"$remote_head"

if [ -z "$default_branch" ]; then
  echo "Warning: unable to determine the default branch of $url; skipping update." >&2
  exit 0
fi

if [ "$current_branch" != "$default_branch" ]; then
  echo "Warning: $path is on $current_branch, not the default branch $default_branch;" \
    "skipping update." >&2
  exit 0
fi

head=$(git -C "$path" rev-parse HEAD)
fetch_ref="refs/git-repo-subscribe/$BASHPID"
trap 'git -C "$path" update-ref -d "$fetch_ref"' EXIT

if ! git -C "$path" fetch --no-write-fetch-head origin \
  "+$default_branch:$fetch_ref"; then
  echo "Warning: unable to fetch $url; skipping update." >&2
  exit 0
fi

if [ "$(git -C "$path" remote get-url origin)" != "$origin_url" ]; then
  echo "Warning: origin URL of $path changed while fetching; skipping update." >&2
  exit 0
fi

if [ "$(git -C "$path" rev-parse HEAD)" != "$head" ]; then
  echo "Warning: HEAD of $path changed while fetching; skipping update." >&2
  exit 0
fi

if [ "$(git -C "$path" symbolic-ref --quiet --short HEAD || true)" != "$current_branch" ]; then
  echo "Warning: branch of $path changed while fetching; skipping update." >&2
  exit 0
fi

if [ -n "$(git -C "$path" status --porcelain=v1 --untracked-files=normal)" ]; then
  echo "Warning: $path gained local changes while fetching; skipping update." >&2
  exit 0
fi

if ! git -C "$path" merge --ff-only --no-overwrite-ignore "$fetch_ref"; then
  echo "Warning: unable to fast-forward $path; skipping update." >&2
fi
