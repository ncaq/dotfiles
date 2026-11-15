/**
  btrfsの重複排除デーモンbeesの、ホストに依らない共通の設定。

  各ホストでは`services.beesd.filesystems`に、
  対象のファイルシステムとハッシュテーブルの大きさなど固有の値だけを書く。
  ここでは全てのインスタンスに負荷の調整のオプションを足す。

  上流のsystemdユニットがNice=19とIOSchedulingClass=idleを設定しているため、
  CPUの優先度は元々アイドル相当。
  ただしNVMeのI/Oスケジューラは`none`なので、
  NVMeではI/Oの優先度の指定は効かない。

  スレッド数の上限は原則として既定のCPUスレッド数に任せて、
  実際に動かすスレッド数はload averageで調整させる。
  他に何も動いていない時はCPUを使い切ってさっさと終わらせ、
  他のプロセスが動き出したらその分だけ縮退する。
  load averageはホスト全体の値で全てのインスタンスが同じものを見るので、
  どのインスタンスもCPUスレッド数を目標にすれば、
  合わせてCPUスレッド数程度に収まる。
*/
{ lib, config, ... }:
let
  cpuThreads = config.local.cpuThreads;
in
{
  options.services.beesd.filesystems = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        config.extraOptions = lib.mkBefore [
          "--loadavg-target"
          "${toString cpuThreads}.0"
          # btrfsカーネル側の遅延ワークキューの飽和を防ぐ。
          # 溜まると無関係なプロセスまでファイルシステムの操作で待たされ、
          # それは優先度の指定では避けられない。
          "--throttle-factor"
          "3.0"
        ];
      }
    );
  };

  config.assertions = [
    {
      assertion = config.services.beesd.filesystems == { } || cpuThreads != null;
      message = "beesのload averageの目標をCPUスレッド数から決めるため、`local.cpuTarget`の設定が必要です。";
    }
  ];
}
