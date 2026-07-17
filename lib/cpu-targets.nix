/**
  CPUモデルごとの最適化コンパイルフラグレジストリ。

  各CPUは基本的に発売日の新しい順に登録する。
  日付コメントは発売日(`YYYY-MM-DD`)を表す。

  キーは`/proc/cpuinfo`の`model name`文字列そのままを採用する。
  ベンダー独自の表記揺れを自分で正規化するよりも、
  カーネルが返す文字列をそのまま流用するほうが事故が少ない。

  各エントリの`arch`は、
  `lib.systems.architectures.features`に登録済みの`gcc.arch`名でなければならず、
  `mkTarget`の`assert`で評価時に検証される。
  これによりnixpkgs側でarch名が変更/削除された際に静かに壊れることを防ぐ。

  `cacheParams`は`gcc -march=native -E -v - </dev/null 2>&1 | grep cc1`の出力から、
  該当CPU上で取得した値を写経する。
  `-march=<arch>`だけではキャッシュ階層ヒントが付与されないため、
  この情報がモデル固有最適化の主要な価値になる。

  `threads`はそのCPUの論理スレッド数(SMT込み、`nproc`相当)を記録する。
  ビルド並列度やコンテナへのCPU割り当てなど、
  評価時に固定値を要する箇所の単一の出典として使う。
  モデル名の`6-Core`等は物理コア数でありこの値とは一致しないので注意する。
*/
{ lib }:
let
  inherit (lib.systems) architectures;

  mkTarget =
    {
      arch,
      threads,
      tune ? arch,
      cacheParams ? [ ],
      extraFlags ? [ ],
    }:
    assert lib.assertMsg (
      architectures.features ? ${arch}
    ) "cpu-targets: unknown arch '${arch}' (not in lib.systems.architectures.features)";
    {
      inherit
        arch
        threads
        tune
        cacheParams
        extraFlags
        ;
    };
in
rec {
  targets = {
    # 2025-03-12
    "AMD Ryzen 9 9950X3D 16-Core Processor" = mkTarget {
      arch = "znver5";
      threads = 32;
      cacheParams = [
        "--param=l1-cache-size=48"
        "--param=l1-cache-line-size=64"
        "--param=l2-cache-size=1024"
      ];
    };

    # 2023-03-05
    "AMD Ryzen 5 PRO 7540U w/ Radeon 740M Graphics" = mkTarget {
      arch = "znver4";
      threads = 12;
      cacheParams = [
        "--param=l1-cache-size=32"
        "--param=l1-cache-line-size=64"
        "--param=l2-cache-size=1024"
      ];
    };

    # 2023-01-14
    "AMD Ryzen 5 7600 6-Core Processor" = mkTarget {
      arch = "znver4";
      threads = 12;
      cacheParams = [
        "--param=l1-cache-size=32"
        "--param=l1-cache-line-size=64"
        "--param=l2-cache-size=1024"
      ];
    };
  };

  /**
    gccやclang向けのCPU最適化フラグ。
  */
  cflagsFor =
    name:
    let
      t = targets.${name};
    in
    [
      "-march=${t.arch}"
      "-mtune=${t.tune}"
      "-O2" # `-O3`は一部のコードで逆効果になる可能性があるため`-O2`相当で止める。
    ]
    ++ t.cacheParams
    ++ t.extraFlags;

  /**
    rustc向けのCPU最適化フラグ。
    `cflagsFor`はGCCドライバ専用構文(`-march`/`--param`)を含み、
    rustcは受け付けないので、
    別関数で対応するフラグに変換する。
    rustcは`-C target-cpu`にgccと同じ`znver5`等を受け付け、
    指定するとマイクロアーキテクチャ向けのfeatureが暗黙で有効になる。
    `-O2`相当は`opt-level`で表現できるが、
    cargoの`release` profileは既定で`opt-level=3`なため、
    profile設定を尊重してここでは設定しない。
    キャッシュ階層ヒントに相当する機構はrustcにはない。
  */
  rustflagsFor =
    name:
    let
      t = targets.${name};
    in
    [
      "-C"
      "target-cpu=${t.arch}"
    ];

  /**
    CPUモデル名からLinuxカーネル向けのCPUターゲットKconfigシンボル名を得る。
    `arch/x86/Kconfig.cpu`の`MZEN`系オプションに対応する。
    XanModカーネルは`graysky2/kernel_compiler_patch`相当のパッチを統合済みで、
    `MZEN`〜`MZEN5`を選択可能。
    Kconfigによる選択は`-march=znver*`の付与に加えて、
    `X86_L1_CACHE_SHIFT`等のアーキテクチャ依存定数や、
    Cソース内の`#ifdef CONFIG_*`分岐にも影響する。
    `KCFLAGS`経由のフラグ注入では得られない構造的最適化が掛かるため、
    こちらの方式を使う。
  */
  kernelOptionFor =
    name:
    let
      t = targets.${name};
      archToKernel = {
        znver1 = "MZEN";
        znver2 = "MZEN2";
        znver3 = "MZEN3";
        znver4 = "MZEN4";
        znver5 = "MZEN5";
      };
    in
    archToKernel.${t.arch} or (throw "cpu-targets: no kernel CPU for arch '${t.arch}'");
}
