{
  pkgs,
  lib,
  config,
  ...
}:
{
  services.tailscale = {
    enable = true;
  };

  systemd.services.tailscale-online = {
    description = "Wait for Tailscale tailnet connection to be established";
    wants = [
      "network-online.target"
      "tailscaled.service"
    ];
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Hardening
      # tailscale CLIはtailscaledのLocalAPIにUNIXソケット経由で接続するだけなので、
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
      ExecStart = lib.getExe (
        pkgs.writeShellApplication {
          name = "wait-for-tailscale";
          runtimeInputs = with pkgs; [
            config.services.tailscale.package
            jq
          ];
          # `tailscale status`の終了コードはtailscaledが応答するだけで成功になり、
          # キャッシュされたログイン状態でも通ってしまうため接続性の保証にならない。
          # `.Self.Online`はコーディネーションサーバに実際に接続できているかを示すので、
          # これがtrueになるまで待つ。
          text = ''
            until tailscale status --json --peers=false | jq -e '.Self.Online == true' > /dev/null 2>&1; do
              sleep 1
            done
          '';
        }
      );
    };
  };
}
