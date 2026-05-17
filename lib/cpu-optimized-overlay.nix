/**
  特定パッケージをCPUモデル固有の最適化フラグでビルドさせるoverlay。

  `lib/cpu-targets.nix`の`cflagsFor`/`rustflagsFor`で得たフラグ群を、
  各コンパイラ向けの環境変数に乗せて`stdenv`のラッパーに渡し、
  対象パッケージのビルドに反映する。
  既存derivationと同じ名前で上書きすることで、
  利用側の参照先を変えずに済む。

  扱う環境変数とカバー範囲:

  - `NIX_CFLAGS_COMPILE`:
    nixpkgsの`cc-wrapper`が、
      - `gcc`
      - `g++`
      - `cpp`
      - `gfortran`
      - `gnat`
      - `gdc`
      - `gccgo`
    などのGCC系フロントエンド全てに共通で付加するため、
      - C
      - C++
      - Objective-C
      - Fortran
      - Ada
      - D(gdc)
      - Go(gccgo)
    などをまとめてカバーする。
    Clang系の`cc-wrapper`も同じ変数を読むのでLLVMビルドも追従する。

  - `NIX_RUSTFLAGS`:
    nixpkgsの`rustc-wrapper`がrustc呼び出し末尾に追記する変数で、
    `NIX_CFLAGS_COMPILE`とcc-wrapperの関係に対応する。
    cargo経由でもcargoが内部で叩くrustcが結局wrapper越しになるため、
    cargoの`RUSTFLAGS`/`CARGO_BUILD_RUSTFLAGS`が排他規則で潰し合っても影響を受けない。
    cargoの`release` profileの`opt-level=3`等もそのまま尊重される。

  上記でカバーされない言語の例:
    - D言語のDMD/LDCといった非GCC系の実装
    - Goの`gc`コンパイラ版
    - Nim
    - Zig
  などはそこまでCPU最適化したいパッケージが現状あまりないのと、
  共通の最適化システムの状況がいまいち不明なので、
  ひとまず対象外にしている。

  `override { stdenv = ...; }`を試して、
  受け付けるパッケージはそちらに切り替えるという案もあったが、
  `pkgs.emacs`のように`override`の形が変則的で、
  `builtins.functionArgs`が通らないケースがあるため、
  全件`overrideAttrs`に統一して安定性を取っている。
*/
cpuName: _final: prev:
let
  cpuTargets = import ../lib/cpu-targets.nix { inherit (prev) lib; };
  cflags = cpuTargets.cflagsFor cpuName;
  rustflags = cpuTargets.rustflagsFor cpuName;

  appendEnv =
    old: name: extra:
    toString (old.env.${name} or "") + " " + builtins.concatStringsSep " " extra;

  optimize =
    drv:
    drv.overrideAttrs (old: {
      env = (old.env or { }) // {
        NIX_CFLAGS_COMPILE = appendEnv old "NIX_CFLAGS_COMPILE" cflags;
        NIX_RUSTFLAGS = appendEnv old "NIX_RUSTFLAGS" rustflags;
      };
    });
in
{
  emacs = optimize prev.emacs;
}
