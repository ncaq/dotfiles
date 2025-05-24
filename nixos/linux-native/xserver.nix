{ pkgs, username, ... }:
{
  services = {
    xserver = {
      enable = true;
      displayManager = {
        lightdm = {
          enable = true;
        };
        session = [
          {
            manage = "desktop";
            name = "hm-xsession";
            start = ''
              # home-managerの`.xsession`が存在しない場合のfallback
              if [ -f "$HOME/.xsession" ]; then
                exec $HOME/.xsession
              else
                # 基本的なXのsessionを開始
                exec ${pkgs.xterm}/bin/xterm
              fi
            '';
          }
        ];
      };
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
}
