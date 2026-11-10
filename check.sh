#!/usr/bin/env bash
set -euo pipefail

# どこから呼ばれてもこのリポジトリのflakeを見ます。
cd "$(dirname "$0")"

# 今のマシンのシステムの`checks`だけを評価します。
# `nix-fast-build`は既定では`.#checks`の全システムを評価しますが、
# `callCabal2nix`のようなIFDは評価するだけで対象のシステムのderivationをビルドするので、
# そのシステムを実行できないマシンでは評価が失敗します。
# ビルドされるのは元から今のシステムの分だけなので、評価も同じ範囲に揃えます。
# flakeの評価は純粋で今のシステムを知れないので、ここで調べて属性を指定します。
system=$(nix eval --raw --impure --expr builtins.currentSystem)

# `--option eval-cache false`は、
# 評価のワーカーが評価キャッシュを取り合って出す競合の警告を抑止するものです。
# 警告が大量に出て結果が読みにくくなるのを防ぐだけで、チェックの結果は変わりません。
# `--no-link`は、
# チェックするだけで`result`リンクが作成されるのを回避するものです。
# `--skip-cached`は、
# ビルドキャッシュがあるものはスキップして高速化するものです。
arguments=(
  --flake ".#checks.$system"
  --option eval-cache false
  --no-link
  --skip-cached
)

# `--no-nom`は、
# 端末を書き換える進捗表示をやめて、ログとして読める出力にするものです。
# CIやコーディングエージェントのように出力が端末ではない時だけ付けます。
if [ ! -t 1 ]; then
  arguments+=(--no-nom)
fi

arguments+=("$@")

# home-managerが入れるラッパーがPATHにあれば、
# メモリに合わせて評価のワーカー数を抑えてくれるのでそれを使います。
# CIのようにPATHに無い環境では、flakeが固定している版を使います。
if command -v nix-fast-build >/dev/null 2>&1; then
  exec nix-fast-build "${arguments[@]}"
else
  exec nix run '.#nix-fast-build' -- "${arguments[@]}"
fi
