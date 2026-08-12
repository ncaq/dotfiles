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
  };
}
