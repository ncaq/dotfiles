# ラップトップでは外出時の一応のセキュリティのためseminarをexit nodeとして使用します。
# ただしseminarと同じローカルネットワークにいる場合は無駄なので通常の通信を行います。
{ pkgs, ... }:
let
  # tailscale pingのレイテンシでローカルネットワークにいるかを判定し、
  # exit nodeの設定を切り替えるスクリプト。
  # ローカルネットワークなら数ms、外部なら数10ms以上になります。
  # セキュリティ的にあまり厳密な判定ではありませんが、
  # そもそもそこまで差し迫ってVPNを使いたいわけではないので許容します。
  tailscaleExitNodeScript = pkgs.writeShellScript "tailscale-exit-node" ''
    set -euo pipefail

    # upイベント以外は無視
    if [ "''${2:-}" != "up" ]; then
      exit 0
    fi

    # Tailscaleが準備できるまでリトライ
    for _ in $(seq 1 10); do
      if ${pkgs.tailscale}/bin/tailscale status > /dev/null 2>&1; then
        break
      fi
      sleep 1
    done

    # tailscale pingでレイテンシを取得
    # 出力例: pong from seminar (100.82.4.93) via 192.168.10.88:41641 in 4ms
    ping_output=$(${pkgs.tailscale}/bin/tailscale ping -c 1 seminar 2>&1) || true
    latency=$(echo "$ping_output" | ${pkgs.gnugrep}/bin/grep -oP 'in \K[0-9]+(?=ms)' || echo "999")

    # レイテンシが10ms以下ならローカルネットワーク
    if [ "$latency" -le 10 ]; then
      echo "seminar latency is ''${latency}ms (local network), disabling exit node"
      ${pkgs.tailscale}/bin/tailscale set --exit-node=
    else
      echo "seminar latency is ''${latency}ms (external network), enabling exit node"
      ${pkgs.tailscale}/bin/tailscale set --exit-node=seminar
    fi
  '';
in
{
  networking.networkmanager.dispatcherScripts = [
    {
      source = tailscaleExitNodeScript;
      type = "basic";
    }
  ];
}
