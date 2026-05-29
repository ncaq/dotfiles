# Nix言語の編集・開発を補助するパッケージ。
{ pkgs, ... }:
let
  # `nix-fast-build`をカスタマイズします。
  # 設定ファイル機能がないので引数を上書きするラッパーを作ることでカスタマイズしています。
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
  nix-fast-build-wrapper = pkgs.writeShellApplication {
    name = "nix-fast-build";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      nix-fast-build
    ];
    text = ''
      # メモリ(swapは除く)の合計量(KiB)。
      mem_total_kib=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
      # 利用して良いメモリの予算(MiB)。
      budget_mib=$(( mem_total_kib / 2 / 1024 ))
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
  };
in
{
  home.packages = with pkgs; [
    cachix
    nil
    nix-diff
    nix-fast-build-wrapper
    nix-init
    nix-update
    nixfmt
    nvd
    update-nix-fetchgit
  ];
}
