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
      # systemdサービスからの起動に使う`steam-gamescope`コマンドの提供元なので有効にしておく。
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
    gamescope.enable = true;
  };
}
