{ pkgs, ... }:
{
  # Homeディレクトリが読み込めないような時でも日本語を表示するために、システム領域にもインストールする。
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-emoji
  ];
}
