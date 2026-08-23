# Open WebUIがbulletのComfyUIへ届く経路を用意する。
#
# 画像生成の`image-generation.nix`と画像編集の`image-edit.nix`が共有する。
#
# Open WebUIのコンテナは自分のnetnsを持っていて、
# MagicDNSの100.100.100.100もtailnetのULAへの経路も持たない。
# そのためTailscale Serviceの名前を直接引くことはできず、
# ホスト側のCaddyで中継する必要がある。
# `bullet/comfyui/ollama.nix`が同じ制約を逆向きに確認している。
#
# `ollama-backend.nix`と同じ構図だが、
# あちらと違って振り分け先はbulletだけなので、
# フェイルオーバーもパッシブヘルスチェックも要らない。
# bulletが落ちていれば画像は生成できない、というだけである。
{ config, ... }:
let
  addr = config.machineAddresses.open-webui;
  port = config.local.openWebui.comfyuiPort;
  tailnet = config.local.tailscale.tailnet;
in
{
  # `caddy.nix`の`:8081`と同じく、ホスト名なしのアドレスにしてHTTPだけで待ち受ける。
  # ホスト名を書くとCaddyが自動HTTPSを有効にしてしまう。
  services.caddy.virtualHosts.":${toString port}".extraConfig = ''
    bind ${addr.host}
    reverse_proxy https://comfyui.${tailnet} {
      # ComfyUIはsocket activationで動いていて、
      # しばらく使っていない状態から最初のリクエストが届くと起動を待つことになる。
      # 実測では`/object_info`が返るまでに14秒かかった。
      # 既定のまま短い猶予で打ち切ると、
      # 使っていない時ほど失敗するという最も困る挙動になる。
      transport http {
        dial_timeout 30s
        response_header_timeout 5m
      }
      # Tailscale Serviceは名前ごとに証明書とVIPを持つので、
      # Hostヘッダも転送先のものへ揃える。
      header_up Host {upstream_hostport}
    }
  '';

  # Open WebUIコンテナのvethからCaddyへの接続を許可する。
  # ここで開くのはComfyUI本体ではなく中継するCaddyだが、
  # その先は認証のないComfyUIなので`ve-+`のワイルドカードでは開けない。
  # ホストのFORWARDはACCEPTなので、
  # 他のコンテナで動く外部由来のコードからも到達できてしまう。
  networking.firewall.interfaces."ve-open-webui".allowedTCPPorts = [ port ];
}
