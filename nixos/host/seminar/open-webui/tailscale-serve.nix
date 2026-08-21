# Open WebUIをTailscale Serviceとしてtailnet内に公開する。
# Funnelではないのでインターネットには公開されない。
#
# 公開するホストはseminarだけなのでService名にホスト名は入れない。
# 推論先の切り替えはOpen WebUIの内側で行うため、
# 利用者から見えるURLはbulletの電源状態によらず変わらない。
{ config, ... }:
let
  addr = config.machineAddresses.open-webui;
  port = config.containers.open-webui.config.services.open-webui.port;
in
{
  imports = [ ../../../../lib/tailscale-serve.nix ];

  local.tailscaleServe.services.open-webui = {
    service = "svc:open-webui";
    label = "Open WebUI";
    inherit port;
  };

  # privateNetworkのコンテナへはホストのCaddyで中継する。
  # `tailscale serve`はリモートのアドレスも転送先にできるが、
  # ヘルプもドキュメントもローカルのサービスを前提にしていて、
  # 環境によっては互換性の警告を出す扱いになっている。
  # Caddyはリダイレクタのために元々このホストで動いていて、
  # `ollama-backend.nix`でもコンテナとの間に立っているので、
  # 中継を1つ挟んでも増える部品は無い。
  #
  # `caddy.nix`の`:8081`と同じく、ホスト名なしのアドレスにしてHTTPだけで待ち受ける。
  # ホスト名を書くとCaddyが自動HTTPSを有効にしてしまう。
  #
  # Caddyの`reverse_proxy`はWebSocketのUpgradeをそのまま通し、
  # `text/event-stream`を検出するとバッファリングも無効にするため、
  # チャットのストリーミング表示のための追加設定は要らない。
  services.caddy.virtualHosts.":${toString port}".extraConfig = ''
    bind 127.0.0.1
    reverse_proxy http://${addr.guest}:${toString port}
  '';
}
