{ pkgs, ... }:
{
  programs.gpg.enable = true;
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
