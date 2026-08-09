# Open WebUIが使うOllamaを、bulletを優先しつつseminarへフォールバックさせる。
#
# bulletのGPU推論はseminarのCPU推論より圧倒的に速いため、
# bulletの電源が入っていればそちらを使いたい。
# ただし優先順位は接続する側だけでは表現できない。
#
# - Open WebUIの`OLLAMA_BASE_URLS`は複数のOllamaを登録できるが、
#   同名モデルへのリクエストは`random.choice`で振り分けられる
# - Tailscale Servicesを複数ノードで広告してもルーティングは、
#   クライアントごとに安定した疑似ランダム順になる
#
# どちらも優先度を指定できないため、
# 前段のCaddyで優先順位付きのフェイルオーバーを行う。
{ config, ... }:
let
  addr = config.machineAddresses.open-webui;
  port = config.local.openWebui.ollamaPort;
  # `tailscale status`で確認できるこのtailnetのMagicDNSのsuffix。
  tailnet = "border-saurolophus.ts.net";
  # 1つの`reverse_proxy`の中でhttpとhttpsのupstreamは混在できないため、
  # seminar自身のOllamaにもHTTPSのTailscale Service経由で繋ぐ。
  # 自分のServiceへの経路はtailscaledの中で完結する。
  upstreams = [
    "https://ollama-bullet.${tailnet}"
    "https://ollama-seminar.${tailnet}"
  ];
in
{
  # `caddy.nix`の`:8081`と同じく、ホスト名なしのアドレスにしてHTTPだけで待ち受ける。
  # ホスト名を書くとCaddyが自動HTTPSを有効にしてしまう。
  services.caddy.virtualHosts.":${toString port}".extraConfig = ''
    bind ${addr.host}
    reverse_proxy ${builtins.concatStringsSep " " upstreams} {
      # 並び順で最初に使えるupstreamを選ぶ。
      lb_policy first
      # 既定の0では他のupstreamへ再試行しないので、
      # bulletが落ちているときにseminarへ回らず502になる。
      lb_try_duration 5s
      lb_try_interval 500ms
      # パッシブヘルスチェックを有効にする。
      # これがないと`lb_policy first`が最初のupstreamを不健全と認識しない。
      # https://github.com/caddyserver/caddy/issues/4432
      fail_duration 30s
      # bulletが落ちているとTailVIPへの接続はRSTではなく無応答になるため、
      # 既定の3秒より短くして`lb_try_duration`の中に収める。
      transport http {
        dial_timeout 1s
      }
      # Tailscale Serviceは名前ごとに証明書とVIPを持つので、
      # Hostヘッダも選ばれたupstreamのものへ揃える。
      header_up Host {upstream_hostport}
    }
  '';

  # Open WebUIコンテナのvethからCaddyへの接続を許可する。
  networking.firewall.interfaces."ve-+".allowedTCPPorts = [ port ];
}
