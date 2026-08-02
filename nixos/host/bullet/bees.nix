{
  # btrfsの重複排除デーモン。
  # 上流のsystemdユニットがNice=19とIOSchedulingClass=idleを設定しているため、
  # CPUとI/Oの優先度は元々アイドル相当。
  services.beesd.filesystems.root = {
    spec = "/";
    # 検出粒度よりメモリ消費を優先して1GBに抑える。
    # 2TB SSD全域に対しては約32KB粒度で、
    # それ未満の細かい重複は見逃す。
    hashTableSizeMB = 1024;
    extraOptions = [
      # 他プロセスが動き出したら縮退。
      "--loadavg-target"
      "8.0"
      # シンプルなスロットリングも併用。
      "--thread-count"
      "8"
      # btrfsカーネル側の遅延ワークキューの飽和を防ぐ。
      "--throttle-factor"
      "2.0"
    ];
  };
}
