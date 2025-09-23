{
  pkgs,
  ...
}:
{
  # 全てのビルド結果を非同期にプライベートキャッシュにpushします。
  systemd.user.services.attic-watch-store-ncaq-private = {
    Unit = {
      Description = "Attic Binary Cache Auto-Push Service for ncaq:private";
      # ネットワークなどの準備が整ってから起動します。
      After = [
        "network-online.target"
        "nix-daemon.service"
      ];
    };

    Service = {
      # クラッシュしてもしばらく後に再起動します。
      # 必須のサービスではないので間隔は長めです。
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

  # 起動時にキャッシュ設定を初期化します。
  systemd.user.services.attic-use-ncaq-private = {
    Unit = {
      Description = "Initialize Attic Cache Configuration";
      After = [
        "network-online.target"
        "nss-lookup.target"
      ];
      Wants = [
        "network-online.target"
        "nss-lookup.target"
      ];
    };

    Service = {
      Type = "oneshot";
      ExecStartPre = "${pkgs.curl}/bin/curl --head --silent --fail --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 5 --retry-all-errors https://nix-cache.ncaq.net/";
      ExecStart = "${pkgs.attic-client}/bin/attic use ncaq:private";
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
