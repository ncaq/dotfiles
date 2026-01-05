{ pkgs, ... }:
{
  services = {
    pcscd.enable = true; # GPGなどと通信をします。
    udev.packages = [ pkgs.yubikey-personalization ];
  };

  environment.systemPackages = with pkgs; [
    yubikey-manager # ykman コマンド - YubiKeyの状態確認やPIN管理に便利。
  ];
}
