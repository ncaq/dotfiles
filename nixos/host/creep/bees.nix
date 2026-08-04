{ pkgs, ... }:
let
  beesUnit = "beesd@root.service";
in
{
  # btrfsの重複排除デーモン。
  # 上流のsystemdユニットがNice=19とIOSchedulingClass=idleを設定しているため、
  # CPUとI/Oの優先度は元々アイドル相当。
  services.beesd.filesystems.root = {
    spec = "/";
    # 検出粒度よりメモリ消費を優先して抑える。
    # 細かい重複は見逃す。
    hashTableSizeMB = 512;
    extraOptions = [
      # 他プロセスが動き出したら縮退。
      # ラップトップなので保守的に、
      # 何か作業を始めて少しでもloadavgが増えたら縮退させます。
      "--loadavg-target"
      "2.0"
      # シンプルなスロットリングも併用。
      "--thread-count"
      "1"
      # btrfsカーネル側の遅延ワークキューの飽和を防ぐ。
      "--throttle-factor"
      "3.0"
    ];
  };
  # 重複排除はそこまで急ぎの処理ではないので、
  # バッテリー駆動中は停止します。
  systemd.services."beesd@root".unitConfig.ConditionACPower = true;
  services.acpid.acEventCommands = ''
    if [ "$(< /sys/class/power_supply/AC/online)" = 1 ]; then
      ${pkgs.systemd}/bin/systemctl start ${beesUnit}
    else
      ${pkgs.systemd}/bin/systemctl stop ${beesUnit}
    fi
  '';
}
