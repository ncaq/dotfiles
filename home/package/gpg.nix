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
    # GPGの証明にパスフレーズは不要だと思うのでキャッシュ時間を長くして実質無制限にします。
    # 証明書を持っていることが重要なのであって、パスフレーズを入力させることにあまり意味は無いと考えています。
    defaultCacheTtl = 157680000; # 5年(60 * 60 * 24 * 365 * 5)
    maxCacheTtl = 157680000;
  };
  home.packages = with pkgs; [
    paperkey
    pinentry-qt # パッケージ指定するだけではなく実際にインストールする必要があります。
  ];
}
