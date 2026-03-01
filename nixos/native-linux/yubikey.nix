{ pkgs, ... }:
{
  # YubiKeyは、
  # GPG対応版はファームウェアのバージョンが5.1.2で古くて楕円曲線暗号に対応しておらず、
  # BioはそもそもGPG機能がないため、
  # GPGには使えていません。
  # FIDO2のために使っています。

  services = {
    udev.packages = [ pkgs.yubikey-personalization ];
  };

  environment.systemPackages = with pkgs; [
    yubikey-manager # ykman コマンド - YubiKeyの状態確認やPIN管理に便利。
    yubikey-personalization # これのコマンドはあまり使いませんが、どうせudevのためにインストールされるので指定。
  ];
}
