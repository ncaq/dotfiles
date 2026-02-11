_: {
  location.provider = "geoclue2";
  services.clight = {
    enable = true;
    settings = {
      # 無操作時に時間経過で暗くするのを無効化。
      # AC接続時には切りたいが、片方だけ切る方法が分からなかった。
      # バッテリー接続時もそんなに頻繁に中途半端に暗くしてもあまり意味がないと思ったので、
      # 諦めて全体を無効化します。
      dimmer.disabled = true;
      dpms = {
        # 無操作時に画面の電源を切るまでの時間。
        ac_timeouts = [ (2 * 60 * 60) ]; # AC電源時: 2時間
        batt_timeouts = [ (10 * 60) ]; # バッテリー時: 10分
      };
    };
  };
  # デフォルトだとclightパッケージが同梱するXDG autostartのdesktopファイルから、
  # systemd-xdg-autostart-generatorがサービスを生成します。
  # そうなるとservices.clightが作成するsystemdユーザーサービスと二重起動して競合するため、
  # autostart側を無効化します。
  # See: https://github.com/NixOS/nixpkgs/pull/262624
  systemd.user.services."app-clight@autostart".enable = false;
}
