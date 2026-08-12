# Tailscale Serviceの80番へ来たHTTPリクエストをHTTPSへリダイレクトするバックエンド。
#
# ブラウザのURL補完やコピーしたリンクからは`http://`で飛ぶことが多いが、
# ServeにHTTPSのリスナーしか無いとTCP接続自体が拒否されて到達できない。
# `tailscale serve`のターゲットはfile、directory、text、URL、UNIXソケットだけで、
# リダイレクトを返す手段が無いため、転送先として最小のHTTPサーバを用意する。
#
# Tailscale ServeはバックエンドへHostヘッダをそのまま渡すので、
# Service名ごとにvhostを分けなくても1つのvhostで全Serviceを賄える。
# 実際にServe経由のリクエストで`Host: comfyui.border-saurolophus.ts.net`が、
# そのまま届くことをbullet上で確認済み。
#
# `nixos/host/seminar/caddy.nix`の`:8081`と同じく、
# ホスト名なしのアドレスにしてHTTPだけで待ち受ける。
# ホスト名を書くとCaddyが自動HTTPSを有効にしてしまう。
#
# Tailscale Serviceが80番を受け付けるには、
# infra.ncaq.netの`tailscale/service.tf`の`ports`と、
# `tailscale/access-policy.tf`のgrantの両方に`tcp:80`が必要。
{ config, ... }:
{
  services.caddy = {
    enable = true;
    virtualHosts.":${toString config.local.tailscaleServe.redirectPort}".extraConfig = ''
      bind 127.0.0.1
      # 301ではなく308を返す。
      # 301はリクエストメソッドの保存が保証されず、
      # POSTがGETへ書き換えられてしまう。
      redir https://{host}{uri} 308
    '';
  };
}
