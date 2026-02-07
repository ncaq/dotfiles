{
  pkgs,
  lib,
  isTermux,
  ...
}:
lib.mkIf (!isTermux) {
  # 全てのビルド結果を非同期にプライベートキャッシュにpushします。
  systemd.user.services.attic-watch-store-ncaq-private = {
    Unit = {
      Description = "Attic Binary Cache Auto-Push Service for ncaq:private";
      # ネットワークなどの準備が整ってから起動します。
      After = [
        "network-online.target"
        "nix-daemon.service"
      ];
      # 設定ファイルが存在しない場合は起動しません。
      ConditionPathExists = [ "%h/.config/attic/config.toml" ];
    };

    Service = {
      # クラッシュしてもしばらく後に再起動します。
      Restart = "on-failure";
      RestartSec = "15s";

      # 必要なパスのみアクセス許可します。
      ReadOnlyPaths = [
        "/nix/store"
        "%h/.config/attic"
      ];
      # 直接コマンド実行
      ExecStart = "${pkgs.attic-client}/bin/attic watch-store ncaq:private";
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
