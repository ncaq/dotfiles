{
  lib,
  isTermux,
  ...
}:
lib.mkIf (!isTermux) {
  # Termux環境ではdconfにアクセス出来ないので無効にします。
  gtk = {
    enable = true;

    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = true;
    };
    # GTK4では`gtk-application-prefer-dark-theme`の後継の`gtk-interface-color-scheme`を使います。
    # 前者はGTK 4.23.1未満のlibadwaitaのアプリケーションに非推奨として警告されます。
    # GTK 4.22のDefaultテーマは前者で暗い配色を選ぶため、
    # libadwaitaを使わないGTK4のアプリケーションは明るい配色になりますが受け入れます。
    gtk4.extraConfig = {
      gtk-interface-color-scheme = "dark";
    };
  };
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };
}
