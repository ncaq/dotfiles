# Caddyを動かすホスト全てに共通の設定。
#
# Caddyのadmin APIは既定で`127.0.0.1:2019`に無認証で開く。
# loadエンドポイントへPOSTすれば設定を丸ごと差し替えられるので、
# 同じホストで動く任意のプロセスが、
# 任意のバックエンドへのプロキシやファイル配信を仕込めてしまう。
# ブラウザや各種ツールがローカルで動くデスクトップでは特に露出が大きい。
#
# 設定は全て静的なので機能としては切ってしまっても困らないが、
# `admin off`にすると`services.caddy.enableReload`が使う`caddy reload`も動かなくなり、
# 設定変更のたびにCaddyの再起動が必要になる。
# UNIXソケットへ移せばreloadを保ったままアクセス元を絞れる。
# Caddyが作るソケットの既定のパーミッションは`0200`なので、
# caddyユーザとroot以外は接続できない。
# `caddy reload`は`--address`を省くと設定ファイルからadminのアドレスを読むため、
# NixOSモジュールが組み立てる`ExecReload`はそのままで通る。
{ lib, config, ... }:
{
  config = lib.mkIf config.services.caddy.enable {
    # `/run`直下はcaddyユーザに書けないのでsystemdにディレクトリを用意させる。
    systemd.services.caddy.serviceConfig.RuntimeDirectory = "caddy";
    # スラッシュが2つ並ぶのはタイプミスではない。
    # `unix/`がCaddyのネットワークアドレス記法のプレフィックスで、
    # 続く`/run/caddy/admin.sock`が絶対パスなので重なる。
    # 1つに減らすと`/run`が相対パス扱いになり待ち受け先が変わる。
    #
    # `globalConfig`は`types.lines`なので他のモジュールの定義と連結される。
    # 他所でadminを書くとCaddyfileの中でadminが重複定義になる。
    services.caddy.globalConfig = ''
      admin unix//run/caddy/admin.sock
    '';
    # 死活監視用のエンドポイント。
    # Caddyには`/health`のようなヘルスチェック専用のエンドポイントが公式には存在せず、
    # admin APIの`/config/`を叩くのが慣習的な代用になっていますが、
    # あれは設定を返すAPIであってHTTPリスナーが実際に応答できるかは分かりません。
    # admin APIがUNIXソケットに移ってTCPから叩けなくなったこともあり、
    # 公式ドキュメントが案内している`respond`で自前のエンドポイントを立てます。
    # https://caddyserver.com/docs/caddyfile/directives/respond
    #
    # `:2020`はadmin APIの既定の`2019`の隣というだけの番号です。
    # ホスト名を書くとlocal CAによる自動HTTPSの対象になってしまうため、
    # ポートだけを書いて`bind`で127.0.0.1に限定し、
    # 同じホストの監視エージェントからのみ届くようにします。
    services.caddy.virtualHosts.":2020".extraConfig = ''
      bind 127.0.0.1
      respond /health 200
    '';
  };
}
