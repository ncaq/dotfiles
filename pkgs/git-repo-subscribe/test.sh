#!/usr/bin/env bash
set -euo pipefail

subscriber=$1
workdir=$(mktemp -d)

remote="$workdir/remote.git"
remote_url="file://$remote"
source_repo="$workdir/source"
subscription="$workdir/subscription"

git init --bare --initial-branch=master "$remote"
git -C "$remote" config uploadpack.allowFilter true
git init --initial-branch=master "$source_repo"
git -C "$source_repo" config user.email test@example.com
git -C "$source_repo" config user.name Test
git -C "$source_repo" remote add origin "$remote"
dd if=/dev/zero of="$source_repo/historical" bs=1M count=2 status=none
historical_blob=$(git -C "$source_repo" hash-object historical)
git -C "$source_repo" add historical
git -C "$source_repo" commit -m historical
unlink "$source_repo/historical"
printf 'initial\n' >"$source_repo/tracked"
git -C "$source_repo" add --all
git -C "$source_repo" commit -m initial
git -C "$source_repo" push -u origin master

"$subscriber" "$remote_url" "$subscription" blob:limit=1m
test "$(git -C "$subscription" rev-list --count HEAD)" = 2
test "$(git -C "$subscription" config --get remote.origin.partialclonefilter)" = blob:limit=1048576
test "$(git -C "$subscription" config --get remote.origin.promisor)" = true
test "$(git -C "$subscription" rev-parse --is-shallow-repository)" = false
if GIT_NO_LAZY_FETCH=1 git -C "$subscription" cat-file -e "$historical_blob" 2>/dev/null; then
  echo "Historical large blob was unexpectedly fetched." >&2
  exit 1
fi

printf 'updated\n' >"$source_repo/tracked"
git -C "$source_repo" commit -am update
git -C "$source_repo" push
"$subscriber" "$remote_url" "$subscription" blob:limit=1m
test "$(git -C "$subscription" rev-parse HEAD)" = "$(git -C "$source_repo" rev-parse HEAD)"

git -C "$subscription" switch -c topic
topic_head=$(git -C "$subscription" rev-parse HEAD)
printf 'branch update\n' >"$source_repo/tracked"
git -C "$source_repo" commit -am branch-update
git -C "$source_repo" push
"$subscriber" "$remote_url" "$subscription" blob:limit=1m
test "$(git -C "$subscription" rev-parse HEAD)" = "$topic_head"

git -C "$subscription" switch master
printf 'dirty\n' >"$subscription/untracked"
dirty_head=$(git -C "$subscription" rev-parse HEAD)
"$subscriber" "$remote_url" "$subscription" blob:limit=1m
test "$(git -C "$subscription" rev-parse HEAD)" = "$dirty_head"

unlink "$subscription/untracked"
git -C "$subscription" switch --detach
detached_head=$(git -C "$subscription" rev-parse HEAD)
"$subscriber" "$remote_url" "$subscription" blob:limit=1m
test "$(git -C "$subscription" rev-parse HEAD)" = "$detached_head"

mkdir "$workdir/not-a-repository"
"$subscriber" "$remote_url" "$workdir/not-a-repository" blob:limit=1m

git -C "$subscription" switch master
mkdir "$subscription/nested"
nested_head=$(git -C "$subscription" rev-parse HEAD)
"$subscriber" "$remote_url" "$subscription/nested" blob:limit=1m
test "$(git -C "$subscription" rev-parse HEAD)" = "$nested_head"

printf 'ignored\n' >>"$subscription/.git/info/exclude"
printf 'local ignored content\n' >"$subscription/ignored"
printf 'remote content\n' >"$source_repo/ignored"
git -C "$source_repo" add ignored
git -C "$source_repo" commit -m ignored
git -C "$source_repo" push
ignored_head=$(git -C "$subscription" rev-parse HEAD)
"$subscriber" "$remote_url" "$subscription" blob:limit=1m
test "$(git -C "$subscription" rev-parse HEAD)" = "$ignored_head"
test "$(<"$subscription/ignored")" = "local ignored content"

unlink "$subscription/ignored"
other_remote="$workdir/other.git"
other_remote_url="file://$other_remote"
git clone --bare "$remote" "$other_remote"
git -C "$source_repo" remote add other "$other_remote"
printf 'other remote\n' >"$source_repo/other"
git -C "$source_repo" add other
git -C "$source_repo" commit -m other
git -C "$source_repo" push other master
git -C "$subscription" remote set-url origin "$other_remote_url"
wrong_origin_head=$(git -C "$subscription" rev-parse HEAD)
"$subscriber" "$remote_url" "$subscription" blob:limit=1m
test "$(git -C "$subscription" rev-parse HEAD)" = "$wrong_origin_head"
