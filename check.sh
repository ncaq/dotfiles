#!/usr/bin/env bash
set -euo pipefail

# どこから呼ばれてもこのリポジトリのflakeを見ます。
cd "$(dirname "$0")"

# 今のマシンのシステムの分だけを評価します。
# `nix-fast-build`は既定では`.#checks`の全システムを評価しますが、
# `callCabal2nix`のようなIFDは評価するだけで対象のシステムのderivationをビルドするので、
# そのシステムを実行できないマシンでは評価が失敗します。
# ビルドされるのは元から今のシステムの分だけなので、評価も同じ範囲に揃えます。
# flakeの評価は純粋で今のシステムを知れないので、ここで調べて属性を指定します。
system=$(nix eval --raw --impure --expr builtins.currentSystem)

# 評価してビルドするflakeの出力。
# 既定の`checks`は、ホストの構成を評価するだけに留めた手元向けの軽いものです。
# CIは`CHECK_OUTPUT=ciJobs`を渡して、
# ホストの構成のビルドとブートテストまで含めたものを1回で処理します。
output=${CHECK_OUTPUT:-checks}

# 評価のワーカ数。
# `nix-fast-build`の既定はCPUスレッド数ですが、
# このリポジトリはホストの構成の評価が1つで数GiBを使うので、メモリに合わせて抑えます。
# `nix-eval-jobs`のワーカは評価中にGCをしないため、確保した分がそのまま使用量になります。
#
# 搭載メモリの半分を予算にして、ワーカ1つあたり3400MiBで割ります。
# 3400MiBは実測から決めた値です。
# 下の`--eval-max-memory-size 1024`を付けた時の評価全体のピークは、
# 時間が頭打ちになるワーカ数(`checks`で6、`ciJobs`で8)までは、
# ワーカを1つ増やすごとに3GiBほど増えました。
# その先は重い属性が残っていないので、増やしてもメモリはあまり増えず、速くもなりません。
# 計測の詳細は https://github.com/ncaq/dotfiles/issues/1752 にあります。
mem_total_kib=0
while read -r key value _; do
  if [ "$key" = MemTotal: ]; then
    mem_total_kib=$value
  fi
done </proc/meminfo
workers=$((mem_total_kib / 2 / 1024 / 3400))
cpu_threads=$(nproc)
if [ "$workers" -gt "$cpu_threads" ]; then
  workers=$cpu_threads
fi
if [ "$workers" -lt 1 ]; then
  workers=1
fi

# `--eval-workers`は、上で求めた評価のワーカ数です。
# `--eval-max-memory-size`は、
# 属性を1つ評価し終えたワーカのメモリがこの値(MiB)を超えていたら、ワーカを作り直すものです。
# 評価の途中では何もしないので、1つの属性が使うメモリを抑えるものではありません。
# 既定の4096では、軽い属性を続けて評価して膨らんだワーカがそのまま重い属性を引きます。
# 1024にすると評価全体のピークが15%から35%下がり、時間はほぼ変わりませんでした。
# 256まで下げると、作り直しが増えて遅くなりました。
# `--option eval-cache false`は、
# 評価のワーカが評価キャッシュを取り合って出す競合の警告を抑止するものです。
# 警告が大量に出て結果が読みにくくなるのを防ぐだけで、チェックの結果は変わりません。
# `--no-link`は、
# チェックするだけで`result`リンクが作成されるのを回避するものです。
# `--skip-cached`は、
# ビルドキャッシュがあるものはスキップして高速化するものです。
arguments=(
  --flake ".#$output.$system"
  --eval-workers "$workers"
  --eval-max-memory-size 1024
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

# このスクリプトへの追加の引数は、そのまま`nix-fast-build`へ渡します。
arguments+=("$@")

# `nix-fast-build`は、このリポジトリのラッパを使います。
# home-managerの環境やセルフホステッドランナのVMのようにPATHにあれば、
# flakeの評価を省けるのでそれを使います。
# PATHに無い環境では、flakeが出している同じラッパを使います。
if command -v nix-fast-build >/dev/null 2>&1; then
  exec nix-fast-build "${arguments[@]}"
else
  exec nix run '.#nix-fast-build' -- "${arguments[@]}"
fi
