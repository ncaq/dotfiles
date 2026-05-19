/**
  LinuxカーネルをCPUモデル固有の最適化Kconfigでビルドさせるoverlay。

  通常のパッケージ向けの`cpu-optimized-overlay.nix`は`NIX_CFLAGS_COMPILE`を、
  `cc-wrapper`経由でコンパイラに渡す方式で、
  これはLinuxカーネルには効かない。
  カーネルの`kbuild`は`KBUILD_CFLAGS`を独自に組み立てており、
  `cc-wrapper`の環境変数を意図的に参照しないため。

  代わりにXanModが取り込んでいる`graysky2/kernel_compiler_patch`相当の、
  CPU選択用Kconfigシンボル(`MZEN4`/`MZEN5`等)を有効化する。
  Kconfigによる選択は`-march=znver*`の付与に加えて、
  `X86_L1_CACHE_SHIFT`等のキャッシュライン定数や、
  Cソース内の`#ifdef CONFIG_*`分岐にも整合性を持って反映される。

  実装方針として、
  `linux_xanmod.override { structuredExtraConfig = ...; }`は使えない。
  `xanmod-kernels.nix`内部で`structuredExtraConfig`が固定的に組み立てられた後、
  `args.argsOverride`で`//`マージされる構造のため、
  そこに上書きを差し込むとXanModが設定した数十項目の既定値を破壊してしまう。

  そのため`kernelPatches`の各要素に含まれる`structuredExtraConfig`が、
  `generic.nix`の`structuredConfigFromPatches`を経由して、
  module評価でマージされるという仕組みを使う。
  これにより既存設定を破壊せずに追加の設定だけを足せる。

  カーネルの最適化設定は取り込んでいるパッチごとに異なるので、
  使う可能性があり設定が容易な一部のカーネルだけ設定しています。
*/
cpuName: _final: prev:
let
  cpuTargets = import ./cpu-targets.nix { inherit (prev) lib; };
  kernelOption = cpuTargets.kernelOptionFor cpuName;
  optimizedKernel = prev.linuxKernel.kernels.linux_xanmod.override (oldArgs: {
    kernelPatches = (oldArgs.kernelPatches or [ ]) ++ [
      {
        name = "cpu-optimized-${kernelOption}";
        patch = null;
        structuredExtraConfig = with prev.lib.kernel; {
          # XanModのデフォルトである`GENERIC_CPU`(x86-64-v1)を外し、
          # CPUモデル固有の最適化オプションを有効化する。
          # `mkForce`を使うのは、
          # XanModの`xanmod-kernels.nix`が`mkOverride 60`で多数の値を設定しており、
          # デフォルト優先度(100)では負けるため。
          GENERIC_CPU = prev.lib.mkForce no;
          ${kernelOption} = prev.lib.mkForce yes;
        };
      }
    ];
  });
in
{
  linuxKernel = prev.linuxKernel // {
    kernels = prev.linuxKernel.kernels // {
      linux_xanmod = optimizedKernel;
    };
    packages = prev.linuxKernel.packages // {
      linux_xanmod = prev.linuxKernel.packagesFor optimizedKernel;
    };
  };
}
