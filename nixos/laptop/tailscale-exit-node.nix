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
    description = ''
      自動的にTailscaleのexit nodeを切り替えます。

      外出時はexit nodeをseminarにします。
      ただしseminarと同じローカルネットワークにいる場合は無駄なので通常の通信を行います。

      切り替えることで家のネットワークのリソースを自然に使えます。
      一応あまり信頼できないネットワーク上でも多重に暗号化をかけることが出来ます。
      普通は今どきTLSなどアプリケーション側で既に暗号化されているはずですが。

      差し迫ったセキュリティ要件が自分にあるわけではないので、
      ローカルネットワークの判定はかなり雑にレイテンシで行っています。
      WIFIのSSIDとかMACアドレスとかはそれはそれで偽装可能なので行っていません。
      真面目にやるとしたらサーバの認証機構などを作るべきでしょうが、
      現在はそこまですることでもないと判断しています。
    '';
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
