{ config, username, ... }:
{
  services.openssh = {
    enable = true;
    # ラップトップなどが信頼できないネットワークに接続することもあるため、
    # firewallの開放は全インターフェイスではなくtailnetに限定する。
    openFirewall = false;
    settings = {
      # パスワード認証を無効化
      PasswordAuthentication = false;
    };
  };
  programs.mosh = {
    enable = true;
    # sshdと同様にtailnetに限定する。
    openFirewall = false;
  };
  # ssh/moshはtailnet越しの接続のみ受け付ける。
  networking.firewall.interfaces.${config.services.tailscale.interfaceName} = {
    allowedTCPPorts = config.services.openssh.ports;
    # nixpkgsのprograms.moshモジュールがopenFirewallで開放する範囲と同じ。
    allowedUDPPortRanges = [
      {
        from = 60000;
        to = 61000;
      }
    ];
  };
  users.users.${username}.openssh.authorizedKeys.keys = [
    # 公開鍵は全世界に公開することが前提として設計されているので、dotfilesに含めて問題ない。

    # GPGエージェントから利用できるSSH鍵。
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGYLEhh/AfM0TcAn15SgUcXZGtS3DxE/7xQmuxApawWg openpgp:0x79E75544"
    # 独立したSSH鍵。
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICl317eHn8HMJgCOVEp3O2VOuj/6rMhq5IbsL2lTTOzQ ncaq@standalone"
  ];
}
