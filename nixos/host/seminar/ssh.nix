{ username, ... }:
{
  services.openssh = {
    enable = true;
    settings = {
      # パスワード認証を無効化
      PasswordAuthentication = false;
    };
  };
  networking.firewall.allowedTCPPorts = [ 22 ];
  users.users.${username}.openssh.authorizedKeys.keys = [
    # 公開鍵は全世界に公開することが前提として設計されているので、dotfilesに含めて問題ない。
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGYLEhh/AfM0TcAn15SgUcXZGtS3DxE/7xQmuxApawWg openpgp:0x79E75544"
    # 旧来の公開鍵です。
    # GPGが完全にセットアップ完了したら削除予定です。
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICTOvA+ciR4NgQKH9yjQke+lMBhSK98VKrnBPRqt2BMt ncaq@bullet"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDUAy/dPVi9oNKSxghttaV1cm9LwUjlplehh6S0lD2rX ncaq@SSD0086"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEFCw2Fj2q9O7gR2JlH1lETW3u8Q2ffCWJGVTFgNVMbX ncaq@creep"
  ];
}
