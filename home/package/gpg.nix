{ pkgs, ... }:
{
  programs.gpg = {
    enable = true;
    publicKeys = [
      {
        trust = "ultimate";
        source = ../ncaq-public-key.asc;
      }
    ];
    scdaemonSettings = {
      # `gpg --card-status`などがドライバの不一致で失敗する問題の対策。
      disable-ccid = true;
      reader-port = "Yubico YubiKey";
    };
  };
  services.gpg-agent = with pkgs; {
    enable = true;
    enableSshSupport = true;
    pinentry.package = pinentry-qt; # pinentry-gnome3はモーダルでパスワードマネージャが使いづらい。
  };
  home.packages = with pkgs; [
    paperkey
    pinentry-qt # パッケージ指定するだけではなく実際にインストールする必要があります。
  ];
}
