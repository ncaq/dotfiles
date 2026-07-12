{ username, ... }:
let
  home-manager-session-name = "hm-xsession";
in
{
  services = {
    xserver = {
      displayManager = {
        session = [
          {
            manage = "desktop";
            name = home-manager-session-name;
            description = ''
              home-manager側で設定した`.xsession`を起動する。
              デフォルトで起動するセッション。
            '';
            start = ''
              exec $HOME/.xsession
            '';
          }
        ];
      };
    };
    displayManager = {
      enable = true;
      sddm.enable = true;
      defaultSession = home-manager-session-name;
      autoLogin = {
        enable = true;
        user = username;
      };
    };
  };
}
