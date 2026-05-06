_: {
  zramSwap = {
    enable = true;
    # swapサイズが大きすぎるせいか、
    # 異常にメモリを消費する動作が起きると、
    # OOM Killerも動かずにシステム全体が固まってしまうことがあります。
    # なのでzramにより設定されるswapサイズを制限します。
    # `memoryPercent`か`memoryMax`のうち小さいほうがサイズになります。
    memoryPercent = 20;
    memoryMax = 6 * 1024 * 1024 * 1024; # 6GB
  };
}
