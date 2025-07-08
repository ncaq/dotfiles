{
  lib,
  inputs,
  isWSL,
  ...
}:
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
    (import ./core { inherit builtins lib inputs; })
    ++ (if isWSL then [ ] else (import ./native-linux { inherit builtins lib inputs; }));
}
