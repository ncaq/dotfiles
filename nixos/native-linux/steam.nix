{ pkgs, ... }:
{
  programs = {
    steam = {
      enable = true;
      # Remote Playのホスト・クライアント通信用にポートを開放。
      remotePlay.openFirewall = true;
      # ローカルネットワーク経由のゲームファイル転送用にポートを開放。
      localNetworkGameTransfers.openFirewall = true;
      # LightDMはこれが登録するWaylandセッションを起動できないが、
      # TTYからの起動に使う`steam-gamescope`コマンドの提供元なので有効にしておく。
      gamescopeSession.enable = true;
      # 互換性問題のあるゲーム向けにProton-GEを導入。
      extraCompatPackages = with pkgs; [ proton-ge-bin ];
      # SteamのFHS環境内で`mangohud %command%`を使えるようにする。
      extraPackages = with pkgs; [ mangohud ];
      # Protonプレフィックスへwinetricksを適用するトラブルシューティングツール。
      protontricks.enable = true;
    };
    # `gamescopeSession`が有効化するが、
    # 単体ゲームのネスト起動にも使うので明示。
    gamemode.enable = true;
    gamescope.enable = true;
  };
  # LightDMはWaylandセッションを起動できず、
  # X11上のネスト起動ではHDRなどを通せないため、
  # 埋め込み(DRM)モードのgamescopeセッションは特定のttyへのログインで起動する。
  # tty4でログインするとlogindセッション経由でDRMマスターを取得して、
  # SteamOS風のフルスクリーンUIが立ち上がる。
  # 終了するとログインプロンプトに戻る。
  # X11のセッションは別VTでそのまま並存する。
  environment.loginShellInit = ''
    if [ "$(tty)" = "/dev/tty4" ]; then
      exec steam-gamescope
    fi
  '';
}
