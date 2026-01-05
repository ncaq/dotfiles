{ pkgs, ... }:
{
  programs.gpg.enable = true;
  services.gpg-agent = with pkgs; {
    enable = true;
    enableSshSupport = true;
    pinentry.package = pinentry-gnome3;
  };
}
