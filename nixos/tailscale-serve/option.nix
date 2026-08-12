# Tailscale Serveのモジュール同士が共有する値を宣言するオプション。
{ lib, ... }:
{
  options.local.tailscaleServe.redirectPort = lib.mkOption {
    type = lib.types.port;
    readOnly = true;
    default = 8880;
    description = ''
      Tailscale ServeのHTTPリスナーが転送する、HTTPSリダイレクタのポート。
      `http-redirect.nix`のCaddyがloopbackで待ち受けて、
      `lib/tailscale-serve.nix`が生成するServeの`--http=80`がここへ転送する。
      待ち受ける側と転送する側の両方が同じ番号を必要とするので1箇所に集める。
    '';
  };
}
