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
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICTOvA+ciR4NgQKH9yjQke+lMBhSK98VKrnBPRqt2BMt ncaq@bullet"
  ];
}
