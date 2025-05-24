# 基本的にビルドした自分のxmonad-launchを使うが、トラブル時の復旧セッションも用意する。
{ pkgs, username, ... }:
{
  services = {
    xserver = {
      enable = true;
      displayManager = {
        lightdm.enable = true;
        session = [
          {
            manage = "desktop";
            name = "hm-xsession";
            description = "home-manager側で設定した `.xsession` を起動する。";
            start = ''
              exec $HOME/.xsession
            '';
          }
        ];
      };
      windowManager.icewm.enable = true;
      xkb = {
        layout = "us";
        model = "pc104";
        variant = "dvorak";
      };
    };
    displayManager = {
      enable = true;
      defaultSession = "hm-xsession";
      autoLogin = {
        enable = true;
        user = username;
      };
    };
    libinput.enable = true;
  };
  environment.systemPackages = with pkgs; [
    rxvt-unicode
    xterm
  ];
}
