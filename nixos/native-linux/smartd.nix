# ディスクのSMARTの値を見張って、
# 寿命や予備領域の残りが交換を考えるべき状態になったことに気付けるようにします。
# 既定の`-a`は値を読むだけで、
# セルフテストのような重い処理は予約しないので、
# クライアントマシンでも有効にします。
# WSLでは物理ディスクが見えないので対象外です。
{ pkgs, ... }:
{
  services.smartd.enable = true;
  # `smartctl`
  environment.systemPackages = [ pkgs.smartmontools ];
}
