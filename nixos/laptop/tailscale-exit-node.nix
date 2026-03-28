# ラップトップでは外出時の一応のセキュリティのためseminarをexit nodeとして使用します。
# ただしseminarと同じローカルネットワークにいる場合は無駄なので通常の通信を行います。
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.custom.tailscale-exit-node;
  # tailscale pingのレイテンシでローカルネットワークにいるかを判定し、
  # exit nodeの設定を切り替えるスクリプト。
  # ローカルネットワークなら数ms、外部なら数10ms以上になります。
  # セキュリティ的にあまり厳密な判定ではありませんが、
  # そもそもそこまで差し迫ってVPNを使いたいわけではないので許容します。
  tailscaleExitNodeScript = lib.getExe (
    pkgs.writeShellApplication {
      name = "tailscale-exit-node";
      runtimeInputs = with pkgs; [
        config.services.tailscale.package
        gnugrep
        systemd
      ];
      text = ''
        # upイベント以外は無視
        if [ "''${2:-}" != "up" ]; then
          exit 0
        fi

        # tailscale-online.serviceでTailscaleの準備完了を待つ
        systemctl start tailscale-online.service

        # tailscale pingでレイテンシを取得
        # 出力例: pong from seminar (100.82.4.93) via 192.168.10.88:41641 in 4ms
        ping_output=$(tailscale ping -c 1 seminar 2>&1) || true
        latency=$(echo "$ping_output" | grep -oP 'in \K[0-9]+(?=ms)' || echo "999")

        # レイテンシが10ms以下ならローカルネットワーク
        if [ "$latency" -le 10 ]; then
          echo "seminar latency is ''${latency}ms (local network), disabling exit node"
          tailscale set --exit-node=
        else
          echo "seminar latency is ''${latency}ms (external network), enabling exit node"
          tailscale set --exit-node=seminar
        fi
      '';
    }
  );
in
{
  options.custom.tailscale-exit-node.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to enable tailscale-exit-node.";
  };

  config = lib.mkIf cfg.enable {
    networking.networkmanager.dispatcherScripts = [
      {
        source = tailscaleExitNodeScript;
        type = "basic";
      }
    ];
  };
}
