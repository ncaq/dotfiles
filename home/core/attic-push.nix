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
      # `attic watch-store`はpushする時に設定をその場で読み込むため事前条件は必須ではありません。
    };
    Service = {
      Restart = "on-failure";
      RestartSec = "15s"; # ネットワークの問題なので少し待ってから再試行します。
      # 必要なパスのみアクセス許可します。
      ReadOnlyPaths = [
        "/nix/store"
        "%h/.config/attic"
      ];
      ExecStart = "${pkgs.attic-client}/bin/attic watch-store ncaq:private";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
