{
  pkgs,
  lib,
  config,
  hardening,
  ...
}:
{
  options.local.tailscale.tailnet = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    default = "border-saurolophus.ts.net";
    description = ''
      `tailscale status`で確認できるこのtailnetのMagicDNSのsuffix。
      ホスト名やService名にこれを付けたものが、tailnet内で引ける名前になる。
    '';
  };

  config = {
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
      # tailscale CLIはtailscaledのLocalAPIにUNIXソケット経由で接続するだけなので、
      # UNIXソケットのみ許可のハードニングまで絞れる。
      # seminar上で同等のサンドボックスを再現して`tailscale status --json`が
      # 動作することを確認済み。
      serviceConfig = hardening.unixSocket // {
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
  };
}
