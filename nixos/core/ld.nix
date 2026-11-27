{ pkgs, ... }:
{
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      alsa-lib
      at-spi2-atk
      at-spi2-core
      atk
      cairo
      cups
      dbus
      expat
      glib
      gtk3
      icu # .NETのグローバリゼーション
      krb5 # .NETのネットワーク認証
      libX11
      libXcomposite
      libXdamage
      libXext
      libXfixes
      libXrandr
      libdrm
      libgbm
      libxcb
      libxkbcommon
      mesa
      nspr
      nss
      pango
    ];
  };
}
