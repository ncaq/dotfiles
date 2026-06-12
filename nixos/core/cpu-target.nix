/**
  ホストのCPUモデルを宣言し、登録済みなら最適化overlayを適用するモジュール。

  `local.cpuTarget`に`/proc/cpuinfo`の`model name`文字列をそのまま設定する。
  `lib/cpu-targets.nix`の`targets`に登録されているCPUのみを`enum`で受け付け、
  未登録のCPU名をうっかり書いた際にはモジュール評価時にエラーで弾く。

  defaultの`null`では何も適用されないため、
  未対応CPUのホストは何も書かなくてよい。
*/
{ lib, config, ... }:
let
  cpuTargets = import ../../lib/cpu-targets.nix { inherit lib; };
  cpuTarget = config.local.cpuTarget;
  # SMTの1物理コア分(2スレッド)はOSやその他プロセスのために空けておく。
  reservedThreads = 2;
in
{
  options.local = {
    cpuTarget = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum (builtins.attrNames cpuTargets.targets));
      default = null;
      example = "AMD Ryzen 9 9950X3D 16-Core Processor";
      description = ''
        `/proc/cpuinfo`の`model name`文字列をそのまま指定する。
        `lib/cpu-targets.nix`に登録されているCPUモデルのみ指定可能。
        未登録のCPUを使うホストは`null`のままにする。
      '';
    };

    cpuBudgetThreads = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default =
        if cpuTarget == null then null else cpuTargets.targets.${cpuTarget}.threads - reservedThreads;
      defaultText = lib.literalMD ''
        `cpuTarget`の論理スレッド数から予約分(${toString reservedThreads}スレッド)を引いた値。
        `cpuTarget`が`null`なら`null`。
      '';
      description = ''
        CIジョブやテストVMなどに割り当ててよいスレッド数。
        全論理スレッドからOSや他プロセス用の予約分を引いた値で、
        ビルド並列度やコンテナのCPU割り当て量の単一の出典として使う。
        `cpuTarget`未登録のホストでは`null`になるため、
        この値を使う側は`cpuTarget`が設定済みであることを前提にする。
      '';
    };
  };

  config = lib.mkIf (config.local.cpuTarget != null) {
    nixpkgs.overlays = [
      (import ../../lib/cpu-optimized-overlay.nix config.local.cpuTarget)
      (import ../../lib/cpu-optimized-kernel-overlay.nix config.local.cpuTarget)
    ];
  };
}
