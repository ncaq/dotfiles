{ pkgs, username, ... }:
{
  # LutrisがProton(umu)経由で起動するゲームでもgamemodeが効くように、
  # `libgamemodeauto.so`のRUNPATHを修正する。
  nixpkgs.overlays = [ (import ../../lib/gamemode-lib-rpath-overlay.nix) ];

  programs = {
    steam = {
      enable = true;
      # Remote Playのホスト・クライアント通信用にポートを開放。
      remotePlay.openFirewall = true;
      # ローカルネットワーク経由のゲームファイル転送用にポートを開放。
      localNetworkGameTransfers.openFirewall = true;
      # LightDMはこれが登録するWaylandセッションを起動できないが、
      # systemdサービスからの起動に使う`steam-gamescope`コマンドの提供元なので有効にしておく。
      gamescopeSession.enable = true;
      # 互換性問題のあるゲーム向けにProton-GEを導入。
      extraCompatPackages = with pkgs; [ proton-ge-bin ];
      # SteamのFHS環境内で`mangohud %command%`を使えるようにする。
      extraPackages = with pkgs; [ mangohud ];
      # Protonプレフィックスへwinetricksを適用するトラブルシューティングツール。
      protontricks.enable = true;
    };
    gamemode.enable = true;
    # `gamescopeSession`が有効化するが、
    # 単体ゲームのネスト起動にも使うので明示。
    gamescope.enable = true;
  };

  # gamemodedはCPUガバナー変更などの特権操作をpkexecで行う。
  # gamemodeが同梱するpolkitルールは`gamemode`グループのユーザにだけ認証なしで許可するので、
  # ユーザをグループに追加する。
  users.users.${username}.extraGroups = [ "gamemode" ];

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
    # Steam外部も含めたアプリをSteamのProtonを使って管理・起動するためのツール。
    # FHS環境にgamemodeのライブラリを追加して、
    # gamemodeautoの`dlopen`が`libgamemode.so`を見つけられるようにする。
    (lutris.override { extraLibraries = pkgs: [ pkgs.gamemode.lib ]; })
    # gamescopeセッションを起動する短縮コマンド。
    (writeShellScriptBin "steamos" ''
      exec systemctl start steam-gamescope.service
    '')
  ];
}
