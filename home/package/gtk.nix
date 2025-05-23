{ pkgs, ... }:
{
  gtk = {
    enable = true;

    theme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };

    iconTheme = {
      name = "gnome";
      package = pkgs.adwaita-icon-theme;
    };

    cursorTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };

    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = true;
    };
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };
}
