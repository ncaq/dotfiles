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
in
{
  options.local.cpuTarget = lib.mkOption {
    type = lib.types.nullOr (lib.types.enum (builtins.attrNames cpuTargets.targets));
    default = null;
    example = "AMD Ryzen 9 9950X3D 16-Core Processor";
    description = ''
      `/proc/cpuinfo`の`model name`文字列をそのまま指定する。
      `lib/cpu-targets.nix`に登録されているCPUモデルのみ指定可能。
      未登録のCPUを使うホストは`null`のままにする。
    '';
  };

  config = lib.mkIf (config.local.cpuTarget != null) {
    nixpkgs.overlays = [
      (import ../../pkgs/cpu-optimized-overlay.nix config.local.cpuTarget)
    ];
  };
}
