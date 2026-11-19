{
  # 負荷の調整は`nixos/native-linux/bees.nix`の共通の設定に任せる。
  services.beesd.filesystems.root = {
    spec = "/";
    # 検出粒度よりメモリ消費を優先して1GBに抑える。
    # 2TB SSD全域に対しては約32KB粒度で、
    # それ未満の細かい重複は見逃す。
    hashTableSizeMB = 1024;
  };
}
