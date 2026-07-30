{ config, ... }:
let
  tailscale = config.services.tailscale.package;
in
{
  # Tailscale Serveの設定。
  # Serveはtailnet内のみに公開する。
  # Caddy :8081がパス毎にtailnet専用サービスをルーティングする。
  #
  # `--bg`は使わずフォアグラウンドで常駐させる。
  # フォアグラウンドのServe設定はCLIプロセスのセッションに紐付き、
  # プロセスが死ぬとtailscaled側が設定を自動で消すため、
  # Serve設定のライフサイクルがユニットのライフサイクルと完全に一致する。
  # `--bg`と違いoffによる明示的な登録解除も、
  # モジュール削除後にtailscaledへ設定が残留する心配も不要になる。
  systemd.services.tailscale-serve = {
    description = "Tailscale Serve";
    requires = [
      "tailscaled.service"
    ];
    wants = [
      "caddy.service"
      "tailscale-online.service"
    ];
    after = [
      "caddy.service"
      "tailscale-online.service"
      "tailscaled.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${tailscale}/bin/tailscale serve --https=8443 http://127.0.0.1:8081";
      # tailscaledの再起動などでセッションが切れるとプロセスが終了するため、
      # 終了コードによらず常に再起動して復帰させる。
      Restart = "always";
      RestartSec = "10s";
      # Hardening
      # tailscale CLIはtailscaledのLocalAPIにUNIXソケット経由で接続してセッションを維持するだけで、
      # 実際のプロキシ転送はtailscaled側が行うため、
      # capabilityも書き込み可能なファイルシステムも不要。
      # 空リストはNixOSモジュールがディレクティブごと省略してしまうため、
      # 空文字列でbounding setを空集合にリセットする。
      CapabilityBoundingSet = "";
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [ "@system-service" ];
    };
  };
}
