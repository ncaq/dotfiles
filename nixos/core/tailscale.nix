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
