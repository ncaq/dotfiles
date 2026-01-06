{ pkgs, ... }:
{
  # YubiKeyは一応持ってるので使えるように設定していますが、
  # ファームウェアのバージョンが現状古くて楕円曲線暗号に対応していないため、
  # 今はあまり使っていません。

  services = {
    pcscd.enable = true; # GPGなどと通信をします。
    udev.packages = [ pkgs.yubikey-personalization ];
  };

  environment.systemPackages = with pkgs; [
    yubikey-manager # ykman コマンド - YubiKeyの状態確認やPIN管理に便利。
  ];
}
