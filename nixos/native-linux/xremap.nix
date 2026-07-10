{
  pkgs,
  username,
  inputs,
  ...
}:
{
  imports = [ inputs.xremap-flake.nixosModules.default ];

  # 共通設定。
  services = {
    xremap = {
      enable = true;
      serviceMode = "user"; # アプリケーションごとに挙動を変えたいのでuserモードを使用。
      userName = username;
      watch = true;
      config = {
        modmap = [
          {
            name = "Global";
            remap = {
              "CapsLock" = "C_L";
            };
          }
        ];
        keymap = [
        ];
      };
    };
  };

  # X11向けの設定。
  services.xremap.withX11 = true;
  systemd.user.services.set-xhost = {
    description = "rootのサービスがユーザーのXセッションにアクセスできるようにする";
    wantedBy = [ "default.target" ];
    path = with pkgs; [ xhost ];
    environment.DISPLAY = ":0.0"; # 番号はハードコードなのでもしブレたらその都度変更します。
    script = "xhost +SI:localuser:root";
  };
}
