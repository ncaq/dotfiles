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

  # ネイティブLinuxに必要だがWSLなどとは干渉するモジュールを分離する。
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
      nativeLinuxImports = [
        ./native-linux/audio.nix
        ./native-linux/networkmanager.nix
        ./native-linux/xserver.nix
      ];
    in
    coreImports ++ (if isWSL then [ ] else nativeLinuxImports);
}
