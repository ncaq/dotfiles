{ pkgs, ... }:
{
  # YubiKeyは一応持ってるので使えるように設定していますが、
  # ファームウェアのバージョンが5.1.2で古くて楕円曲線暗号に対応していないため、
  # 現状GPGには使えていません。

  services = {
    pcscd.enable = true; # GPGなどと通信が出来るように。
    udev.packages = [ pkgs.yubikey-personalization ];
  };

  environment.systemPackages = with pkgs; [
    yubikey-manager # ykman コマンド - YubiKeyの状態確認やPIN管理に便利。
    yubikey-personalization # よりEasyなYubiKeyの設定ツール。
  ];
}
