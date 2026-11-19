{ lib, config, ... }:
let
  beesUnit = "beesd@root.service";
  systemctl = lib.getExe' config.systemd.package "systemctl";
in
{
  # 重複排除はそこまで急ぎの処理ではないので、
  # バッテリ駆動中は停止します。
  # AC電源の時はデスクトップと同じく、
  # 他に何も動いていない時はCPUを使い切ってさっさと終わらせます。
  systemd.services."beesd@root".unitConfig.ConditionACPower = true;
  services = {
    # 負荷の調整は`nixos/native-linux/bees.nix`の共通の設定に任せる。
    beesd.filesystems.root = {
      spec = "/";
      # 検出粒度よりメモリ消費を優先して抑える。
      # 細かい重複は見逃す。
      hashTableSizeMB = 512;
    };
    # `ConditionACPower`は起動する時にしか確かめられないので、
    # 動いている間に電源を抜き差しした時は、ここで停止と起動をします。
    acpid.acEventCommands = ''
      if [ "$(< /sys/class/power_supply/AC/online)" = 1 ]; then
        ${systemctl} start ${beesUnit}
      else
        ${systemctl} stop ${beesUnit}
      fi
    '';
  };
}
