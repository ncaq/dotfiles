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
    reverse_proxy http://${addr.guest}:${toString port} {
      # コンテナのnspawnがbootを終えた時点では、
      # 中のOpen WebUIはまだlistenしていないので接続は拒否される。
      # 既定ではそれをそのまま502として返すため、
      # 起動を待ちたい`blue-prompt.nix`の同期は1試行を0秒で使い潰してしまう。
      # 接続できるまで再試行して、
      # socket activationのsocketが疎通まで接続を保留していた頃の猶予へ戻す。
      # 再試行が起きるのは転送先が居ない時だけなので定常状態のコストは無い。
      lb_try_duration 5s
      lb_try_interval 500ms
    }
  '';
}
