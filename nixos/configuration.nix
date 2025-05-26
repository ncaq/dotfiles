{ isWSL, ... }:
{
  system.stateVersion = "25.05";

  i18n.defaultLocale = "ja_JP.UTF-8";
  time.timeZone = "Asia/Tokyo";

  console.keyMap = "dvorak";

  programs = {
    nix-ld.enable = true;
    zsh.enable = true;
  };

  # Linuxネイティブに必要だがWSLなどとは干渉するモジュールを分離する。
  imports =
    let
      coreImports = [
        ./core/dconf.nix
        ./core/font.nix
        ./core/locate.nix
        ./core/networking.nix
        ./core/nix-settings.nix
        ./core/sudo.nix
        ./core/uinput.nix
        ./core/user.nix
      ];
      linuxNativeImports = [
        ./linux-native/audio.nix
        ./linux-native/networkmanager.nix
        ./linux-native/xserver.nix
      ];
    in
    coreImports ++ (if isWSL then [ ] else linuxNativeImports);
}
