{ ... }:
{
  services.openssh = {
    enable = true;
    settings = {
      # パスワード認証を無効化
      PasswordAuthentication = false;
    };
  };
  networking.firewall.allowedTCPPorts = [ 22 ];
}
