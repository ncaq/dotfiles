# ラップトップでは外出時のセキュリティのため、seminarをexit nodeとして使用する。
# ただし、seminarと同じローカルネットワークにいる場合は通常の通信を行う。
{ pkgs, ... }:
let
  # seminarがローカルネットワークにいるかをavahi(mDNS)で確認し、
  # exit nodeの設定を切り替えるスクリプト。
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

    # seminar.localにpingできるかでローカルネットワーク判定
    if ${pkgs.iputils}/bin/ping -c 1 -W 2 seminar.local > /dev/null 2>&1; then
      echo "seminar.local is reachable, disabling exit node"
      ${pkgs.tailscale}/bin/tailscale set --exit-node=
    else
      echo "seminar.local is not reachable, enabling exit node via seminar"
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
