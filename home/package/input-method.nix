{ pkgs, ... }:
{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-configtool
      fcitx5-gtk
      fcitx5-mozc-ut
    ];
  };

  home.packages = with pkgs.ibus-engines; [
    mozc-ut
  ];
}
