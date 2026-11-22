{
  lib,
  config,
  ...
}:
{
  # ユニットの定義と、探す場所の決め方は、パッケージの隣にある。
  # 権限の絞り込みがコマンドの動きと対になっていて、パッケージのテストもそのユニットを動かすため。
  imports = [ ../../pkgs/trash-empty-stray/module.nix ];

  options.local.trash.retentionDays = lib.mkOption {
    type = lib.types.ints.positive;
    default = 7;
    description = ''
      ゴミ箱へ入れてからこの日数が経ったものを消す。
      Sambaのゴミ箱のように別の仕組みで掃除するものも、保持期間が食い違わないようにここを参照する。
    '';
  };

  config.services.trash-empty = {
    enable = true;
    inherit (config.local.trash) retentionDays;
  };
}
