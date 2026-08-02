# bulletの電源が入っている時に他の端末からもComfyUIを使えるように、
# Tailscale Serveでtailnet内に公開する。
# Funnelではないのでインターネットには公開されない。
# 転送先はcomfyui-proxy.socketなので、
# tailnet経由の初回アクセスでもソケットアクティベーションによるオンデマンド起動が機能する。
# LoRA Managerは`/loras_static`などのルート絶対URLを使うため、
# 専用のTailscale Service `svc:comfyui`のルートへ公開する。
{ config, hardening, ... }:
let
  tailscale = config.services.tailscale.package;
  port = config.containers.comfyui.config.services.comfyui.port;
  service = "svc:comfyui";
in
{
  systemd.services.tailscale-serve-comfyui = {
    description = "Tailscale Serve for ComfyUI";
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
    # tailscale CLIはtailscaledのLocalAPIにUNIXソケット経由で接続するだけで、
    # 実際のプロキシ転送はtailscaled側が行うため、
    # UNIXソケットのみ許可のハードニングまで絞れる。
    # このサンドボックス下でServiceの登録、
    # drainによる停止、
    # 再起動での再advertise、
    # 公開URLへのHTTPSアクセスが通ることをbullet上で確認済み。
    serviceConfig = hardening.unixSocket // {
      Type = "oneshot";
      RemainAfterExit = true;
      # Tailscale Serviceは設定をtailscaledへ永続化してコマンド自体は終了する。
      ExecStart = "${tailscale}/bin/tailscale serve --service=${service} --https=443 http://127.0.0.1:${toString port}";
      # endpoint設定は残して、次回起動時にそのまま再advertiseできるようにする。
      ExecStop = "${tailscale}/bin/tailscale serve drain ${service}";
    };
  };
}
