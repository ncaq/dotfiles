# `nix-fast-build`をカスタマイズするラッパー。
# 設定ファイル機能がないので引数を上書きするラッパーを作ることでカスタマイズしています。
#
# `--no-link`は、
# チェックするだけで`result`リンクが作成されるのを回避するものです。
# `--skip-cached`は、
# ビルドキャッシュがあるものはスキップして高速化するものです。
# `--eval-workers`は、
# 評価フェーズで生成される`nix-eval-jobs`ワーカー数の上限です。
# `nix-fast-build`がメモリを食い尽くさないように、
# ランタイムにシステム搭載メモリの50%を予算として計算して、
# `nix-eval-jobs`の`--max-memory-size`デフォルトである`4GiB`/workerで割って算出します。
# 同時にCPUコア数も上限とすることで、
# メモリに余裕がある環境で評価ワーカーがCPU数を超えて無駄に増えるのを防ぎます。
#
# 環境変数`NIX_FAST_BUILD_CONCURRENT_JOBS`に、
# 同じマシンで同時に動き得る`nix-fast-build`の数を渡すと、
# メモリの予算をその数で割ります。
# 渡さなければ1つだけ動くものとして扱います。
#
# home-managerの環境と、
# GitHub ActionsのセルフホステッドランナーのVMに入れます。
# flakeの`packages`の`nix-fast-build`としても出しているので、
# `./check.sh`はPATHに無い環境でも同じラッパーを使います。
{
  writeShellApplication,
  coreutils,
  gawk,
  nix-fast-build,
}:
writeShellApplication {
  name = "nix-fast-build";
  runtimeInputs = [
    coreutils
    gawk
    nix-fast-build
  ];
  text = ''
    # メモリ(swapは除く)の合計量(KiB)。
    mem_total_kib=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
    # 同じマシンで同時に動き得る`nix-fast-build`の数。
    # このラッパーは他のジョブがメモリを使っていることを知らないので、
    # 複数のジョブが重なる環境では呼び出す側が数を教えます。
    concurrent_jobs=''${NIX_FAST_BUILD_CONCURRENT_JOBS:-1}
    if ! [[ "$concurrent_jobs" =~ ^[1-9][0-9]*$ ]]; then
      echo "NIX_FAST_BUILD_CONCURRENT_JOBSが正の整数ではないので1として扱います: $concurrent_jobs" >&2
      concurrent_jobs=1
    fi
    # 利用して良いメモリの予算(MiB)。
    budget_mib=$(( mem_total_kib / 2 / 1024 / concurrent_jobs ))
    # 4GiBのデフォルト値と予算から求められる利用可能なワーカー数。
    workers=$(( budget_mib / 4096 ))
    # CPUスレッド数も考えて上限にする。
    nproc_value=$(nproc)
    if [ "$workers" -gt "$nproc_value" ]; then
      # CPUコア数がメモリ予算を上回ったらコア数を上限にする。
      workers=$nproc_value
    fi
    if [ "$workers" -lt 1 ]; then
      # 最低限1つのワーカーは保証。
      workers=1
    fi

    exec nix-fast-build \
      --no-link \
      --skip-cached \
      --eval-workers "$workers" \
      "$@"
  '';
}
