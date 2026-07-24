# bulletの電源が入っている時に他の端末からもComfyUIを使えるように、
# Tailscale Serveでtailnet内に公開する。
# Funnelではないのでインターネットには公開されない。
# 転送先はcomfyui-proxy.socketなので、
# tailnet経由の初回アクセスでもソケットアクティベーションによるオンデマンド起動が機能する。
# 何のサービスか分かりやすいように、
# また将来他のサービスも公開できるように、
# ルートではなく`/comfy-ui`パスにマウントする。
#
# `--bg`は使わずフォアグラウンドで常駐させる。
# フォアグラウンドのServe設定はCLIプロセスのセッションに紐付き、
# プロセスが死ぬとtailscaled側が設定を自動で消すため、
# Serve設定のライフサイクルがユニットのライフサイクルと完全に一致する。
# `--bg`と違いoffによる明示的な登録解除も、
# モジュール削除後にtailscaledへ設定が残留する心配も不要になる。
{ config, ... }:
let
  tailscale = config.services.tailscale.package;
  port = config.containers.comfyui.config.services.comfyui.port;
in
{
  systemd.services.tailscale-serve = {
    description = "Tailscale Serve";
    requires = [
      "tailscaled.service"
    ];
    wants = [
      "comfyui-proxy.socket"
      "tailscale-online.service"
    ];
    after = [
      "comfyui-proxy.socket"
      "tailscale-online.service"
      "tailscaled.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${tailscale}/bin/tailscale serve --https=443 --set-path=/comfy-ui http://127.0.0.1:${toString port}";
      # tailscaledの再起動などでセッションが切れるとプロセスが終了するため、
      # 終了コードによらず常に再起動して復帰させる。
      Restart = "always";
      RestartSec = "10s";
    };
  };
}
