{ pkgs, ... }:
let
  keyConfig = import ../../key;
in
{
  programs.gpg = {
    enable = true;
    publicKeys = [
      {
        trust = "ultimate";
        source = keyConfig.publicKeyFile;
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
    # SSH認証に使用するGPGサブキーのkeygrip。
    # `gpg --list-keys --with-keygrip`で[A]能力を持つサブキーのkeygripを確認できる。
    sshKeys = [
      "29C212A380A9E2977752FA41C35A2F9BF6CA24E2" # 認証サブキー 0xACA66AB679E75544
    ];
  };
  home.packages = with pkgs; [
    paperkey
    pinentry-qt # パッケージ指定するだけではなく実際にインストールする必要があります。
  ];
}
