# `nixos/core/caddy.nix`がCaddyを有効にした全ホストに効かせる設定を確認します。
# 判定条件をTailscale Serviceの有無ではなくCaddyの有無にしているのはそのためです。
{
  lib,
  pkgs,
  config,
  ...
}:
let
  curl = lib.getExe pkgs.curl;

  # admin APIをUNIXソケットへ移せているかを確認します。
  # 設定が外れてもCaddyは既定の`127.0.0.1:2019`で普通に起動してしまうので、
  # 他のテストは全て通ったまま無言で退行します。
  admin = # python
    ''
      machine.wait_for_unit("caddy.service")
      machine.succeed("test -S /run/caddy/admin.sock")
      machine.fail("${curl} --fail --silent --max-time 3 http://127.0.0.1:2019/config/")
    '';

  # 死活監視用のエンドポイントを確認します。
  # 監視エージェントがここを叩いているので、
  # パスやポートが変わると監視だけが静かに落ちます。
  # 127.0.0.1に限定できているかも合わせて見ます。
  health = # python
    ''
      machine.wait_for_open_port(2020, "127.0.0.1")
      machine.succeed("${curl} --fail --silent --max-time 3 http://127.0.0.1:2020/health")
      machine.fail("${curl} --fail --silent --max-time 3 http://[::1]:2020/health")
    '';
in
lib.optionalString config.services.caddy.enable (admin + health)
