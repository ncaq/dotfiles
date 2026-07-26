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
      # ラップトップなので最も保守的に、
      # 何か作業を始めてloadavgが1を超えたら即座に全スレッドを停止させる。
      "--loadavg-target"
      "1.0"
      # シンプルなスロットリングも併用。
      "--thread-count"
      "1"
      # btrfsカーネル側の遅延ワークキューの飽和を防ぐ。
      "--throttle-factor"
      "2.0"
    ];
  };
}
