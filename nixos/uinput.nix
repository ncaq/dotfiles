{ ... }:
{
  # 主にxkeysnailが要求します。
  services.udev.extraRules = ''
    KERNEL=="uinput", GROUP="input"
  '';
}
