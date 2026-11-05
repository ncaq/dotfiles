{
  pkgs,
  lib,
  config,
  hardening,
  ...
}:
{
  options.local.tailscale = {
    tailnet = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = import ../../lib/tailnet.nix;
      description = ''
        `tailscale status`で確認できるこのtailnetのMagicDNSのsuffix。
        ホスト名やService名にこれを付けたものが、tailnet内で引ける名前になる。
      '';
    };
    # Tailscaleが全tailnetで使う固定のアドレス範囲。
    # firewallで「tailnetからの通信」を送信元や宛先のアドレスで表す時の単一の出典。
    # https://tailscale.com/kb/1015/100.x-addresses
    # https://tailscale.com/kb/1033/ip-and-dns-addresses
    ipv4Range = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "100.64.0.0/10";
      description = "Tailscaleが各ノードへ割り当てるIPv4アドレスの範囲(CGNAT空間)。";
    };
    ipv6Range = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "fd7a:115c:a1e0::/48";
      description = "Tailscaleが各ノードへ割り当てるIPv6アドレスの範囲(ULA)。";
    };
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
