# ラップトップでは外出時のセキュリティのため、seminarをexit nodeとして使用する。
# ただし、seminarと同じローカルネットワークにいる場合は通常の通信を行う。
{ pkgs, ... }:
let
  # seminarへの接続がダイレクトかDERP経由かで、
  # ローカルネットワークにいるかを判定し、exit nodeの設定を切り替えるスクリプト。
  # tailscale pingを使うことでmDNS偽装攻撃を防ぐ。
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

    # tailscale pingでダイレクト接続かDERP経由かを判定
    # DERP経由ならローカルネットワーク外なのでexit nodeを有効化
    if ${pkgs.tailscale}/bin/tailscale ping -c 1 seminar 2>&1 | ${pkgs.gnugrep}/bin/grep -q "via DERP"; then
      echo "seminar is reachable via DERP, enabling exit node"
      ${pkgs.tailscale}/bin/tailscale set --exit-node=seminar
    else
      echo "seminar is reachable directly, disabling exit node"
      ${pkgs.tailscale}/bin/tailscale set --exit-node=
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
