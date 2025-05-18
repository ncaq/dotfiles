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

  xdg.configFile = {
    # profileは頻繁にfcitxが自動で書き換えるため、強制的に上書きする
    "fcitx5/profile" = {
      force = true;
      text = ''
        [Groups/0]
        # Group Name
        Name=デフォルト
        # Layout
        Default Layout=us-dvorak
        # Default Input Method
        DefaultIM=keyboard-us-dvorak
        [Groups/0/Items/0]
        # Name
        Name=mozc
        # Layout
        Layout=
        [Groups/0/Items/1]
        # Name
        Name=keyboard-us-dvorak
        # Layout
        Layout=
        [GroupOrder]
        0=デフォルト
      '';
    };
  };
}
