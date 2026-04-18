{ username, ... }:
{
  services.openssh = {
    enable = true;
    settings = {
      # パスワード認証を無効化
      PasswordAuthentication = false;
    };
  };
  programs.mosh.enable = true;
  users.users.${username}.openssh.authorizedKeys.keys = [
    # 公開鍵は全世界に公開することが前提として設計されているので、dotfilesに含めて問題ない。
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGYLEhh/AfM0TcAn15SgUcXZGtS3DxE/7xQmuxApawWg openpgp:0x79E75544"
  ];
}
