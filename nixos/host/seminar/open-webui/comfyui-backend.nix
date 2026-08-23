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
{ lib, config, ... }:
let
  addr = config.machineAddresses.open-webui;
  port = config.local.openWebui.comfyuiPort;
  tailnet = config.local.tailscale.tailnet;
  # 公開する側のbulletの`comfyui/tailscale-serve.nix`と同じ定義から名前を組み立てる。
  # `ollama-backend.nix`が`lib/ollama-tailscale-service.nix`でしているのと同じである。
  comfyuiService = import ../../../../lib/comfyui-tailscale-service.nix;
  upstream = "https://${lib.removePrefix "svc:" comfyuiService}.${tailnet}";
in
{
  # `caddy.nix`の`:8081`と同じく、ホスト名なしのアドレスにしてHTTPだけで待ち受ける。
  # ホスト名を書くとCaddyが自動HTTPSを有効にしてしまう。
  services.caddy.virtualHosts.":${toString port}".extraConfig = ''
    bind ${addr.host}
    reverse_proxy ${upstream} {
      # connectに失敗した時に同じ上流へ張り直す猶予。
      #
      # `dial_timeout`を短くしただけだと、
      # 1秒で返らなかった時点で502が確定してリクエストそのものを失う。
      # 接続先はtailnetのVIPなので、
      # bulletが稼働していても直接経路が落ちてDERP経由へ切り替わる瞬間など、
      # 最初のTCP接続に1秒以上かかることは起こり得る。
      # そこで数分かかる生成をやり直させるのは高くつく。
      #
      # `ollama-backend.nix`の`dial_timeout 1s`は、
      # `lb_try_duration`の中で次の候補へ移るための値だった。
      # あちらへ揃える時にその前提が落ちていたので、猶予の方も足す。
      lb_try_duration 3s
      lb_try_interval 250ms
      # ComfyUIはsocket activationで動いていて、
      # しばらく使っていない状態から最初のリクエストが届くと起動を待つことになる。
      # 実測では`/object_info`が返るまでに14秒かかった。
      #
      # ただしその14秒はconnectの後の区間なので、
      # 受け持つのは`response_header_timeout`であって`dial_timeout`ではない。
      # socket activationではsystemd側のsocketが常にlistenしているため、
      # TCPのconnect自体は起動待ちと関係なく即座に完了する。
      #
      # `dial_timeout`はむしろ短くする。
      # bulletの電源が入っていない時、
      # tailnetのVIPへの接続はRSTを返さず無応答になるので、
      # 長くするとその分だけ失敗の検知が遅れて画像1枚あたりの待ち損になる。
      # 上流は1つでフェイルオーバー先も無いため、待っても得るものがない。
      # `ollama-backend.nix`が同じ理由で同じ値を使っている。
      transport http {
        dial_timeout 1s
        response_header_timeout 5m
        # アイドル接続を抱え続けると、bulletが落ちた後もプールに残った接続へ投げてしまう。
        # tailnetの経路が消えるだけでソケットは開いたままに見えるため、
        # 接続し直さない限り`dial_timeout`が効かず、
        # 失敗を検知するまで`response_header_timeout`の5分を待つことになる。
        # 既定の2分は長すぎるので、次のリクエストが繋ぎ直す程度まで縮める。
        # `ollama-backend.nix`が同じ理由で同じ値を使っている。
        # 生成にかかる時間の長さに比べれば接続確立のオーバーヘッドは誤差レベル。
        keepalive 5s
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
