{ pkgs, username, ... }:
{
  # LightDMはWaylandセッションを起動できず、
  # X11上のネスト起動ではHDRなどを通せないため、
  # 埋め込み(DRM)モードのgamescopeセッションをsystemdサービスとして定義する。
  # nixpkgsの`services.cage`(kioskモジュール)と同じパターンで、
  # `PAMName`によるPAM経由の起動でlogindセッションを登録して、
  # ディスプレイマネージャなしでDRMマスターを取得する。
  # `wantedBy`を指定していないので自動起動はせず、
  # `steamos`コマンド(後述)で起動した時だけVT4に立ち上がる。
  # X11のセッションは別VTでそのまま並存して、
  # gamescopeを終了するとサービスも終了する。
  systemd.services.steam-gamescope = {
    description = "Steam gamescope session (embedded DRM) on tty4";
    after = [
      "getty@tty4.service"
      "systemd-logind.service"
      "systemd-user-sessions.service"
    ];
    wants = [
      "dbus.socket"
      "systemd-logind.service"
    ];
    conflicts = [ "getty@tty4.service" ];
    # ゲームプレイ中に`nixos-rebuild switch`してもセッションを殺さない。
    restartIfChanged = false;
    unitConfig.ConditionPathExists = "/dev/tty4";
    serviceConfig = {
      # `+`プレフィックスでroot権限でVTを切り替えてから起動する。
      ExecStartPre = "+${pkgs.kbd}/bin/chvt 4";
      ExecStart = "/run/current-system/sw/bin/steam-gamescope";
      User = username;
      IgnoreSIGPIPE = "no";
      # (a)gettyを置き換えるためutmpにセッションを記録する。
      UtmpIdentifier = "tty4";
      UtmpMode = "user";
      TTYPath = "/dev/tty4";
      TTYReset = "yes";
      TTYVHangup = "yes";
      TTYVTDisallocate = "yes";
      # VTを制御できない場合は起動を失敗させる。
      StandardInput = "tty-fail";
      StandardOutput = "journal";
      StandardError = "journal";
      # PAM経由でlogindセッションを登録する。
      PAMName = "login";
      # systemd v254以降のpam_systemdはローカルセッションへ、
      # ambient capabilityとして`CAP_WAKE_ALARM`をデフォルトで付与する。
      # それがsteam(buildFHSEnvのbwrap)まで伝播すると、
      # bwrapが`Unexpected capabilities but not setuid`エラーで即死してSteamが起動しない。
      # https://github.com/containers/bubblewrap/issues/380
      # bounding setから除外しておけば、
      # PAMセッション開始後にsystemdがambient setを再適用する際に確実に落とされる。
      CapabilityBoundingSet = "~CAP_WAKE_ALARM";
    };
  };

  # `steam-gamescope.service`に限って一般ユーザがpolkit認証なしで操作できるようにして、
  # `steamos`コマンドをsudoなしで打てるようにする。
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "steam-gamescope.service" &&
          subject.user == "${username}") {
        return polkit.Result.YES;
      }
    });
  '';

  environment.systemPackages = with pkgs; [
    # gamescopeセッションを起動する短縮コマンド。
    (writeShellScriptBin "steamos" ''
      exec systemctl start steam-gamescope.service
    '')
  ];
}
