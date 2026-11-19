{
  # 負荷の調整は`nixos/native-linux/bees.nix`の共通の設定に任せる。
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
        # HDDではスレッドを増やしてもシークが増えるだけで速くならないので、
        # 例外としてスレッド数の上限を指定する。
        "--thread-count"
        "2"
      ];
    };
  };
}
