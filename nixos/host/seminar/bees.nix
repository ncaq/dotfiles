{
  # btrfsの重複排除デーモン。
  # 上流のsystemdユニットがNice=19とIOSchedulingClass=idleを設定しているため、
  # CPUとI/Oの優先度は元々アイドル相当。
  #
  # 同一btrfsファイルシステムに複数インスタンスを向けてはいけないが、
  # rootとnoaは完全に独立したファイルシステムなので問題ない。
  services.beesd.filesystems = {
    root = {
      spec = "/";
      # 検出粒度よりメモリ消費を優先して1GBに抑える。
      # 2TB SSD全域に対しては約32KB粒度で、
      # それ未満の細かい重複は見逃す。
      hashTableSizeMB = 1024;
      extraOptions = [
        # 他プロセスが動き出したら縮退。
        "--loadavg-target"
        "3.0"
        # シンプルなスロットリングも併用。
        "--thread-count"
        "3"
        # btrfsカーネル側の遅延ワークキューの飽和を防ぐ。
        "--throttle-factor"
        "1.0"
      ];
    };
    noa = {
      spec = "/mnt/noa";
      # 検出粒度よりメモリ消費を優先して1GBに抑える。
      # 現在の使用量約2.9TiBに対しては約46KB粒度で、
      # 現在の最大容量12.7TiB全域に対しては約200KB粒度と粗いが、
      # HDDでは細かい重複まで共有するほど空き領域の断片化が進むため、
      # 粗い粒度は断片化抑制の面ではむしろ好都合。
      hashTableSizeMB = 1024;
      extraOptions = [
        # 他プロセスが動き出したら縮退。
        "--loadavg-target"
        "3.0"
        # シンプルなスロットリングも併用。
        "--thread-count"
        "3"
        # btrfsカーネル側の遅延ワークキューの飽和を防ぐ。
        "--throttle-factor"
        "1.0"
      ];
    };
  };
}
