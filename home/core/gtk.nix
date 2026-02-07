{
  lib,
  isTermux,
  ...
}:
lib.mkMerge [
  {
    gtk = {
      enable = true;

      gtk3.extraConfig = {
        gtk-application-prefer-dark-theme = true;
      };
      gtk4.extraConfig = {
        gtk-application-prefer-dark-theme = true;
      };
    };
  }
  (lib.mkIf (!isTermux) {
    # Termux環境ではdconfにアクセス出来ないので無効にします。
    dconf.settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
      };
    };
  })
]
