# `caddy.nix`がCaddyを有効にした全ホストに効かせる設定を確認します。
#
# systemd-nspawnのコンテナの中で、`caddy.nix`だけを読み込んでCaddyを有効にしたマシンを動かします。
# Caddyを有効にしたホストの全てに同じ設定が入るので、ホストをブートするテストではなくここに置いています。
# 実行するnix-daemonに要る設定は`nix-daemon.nix`に書いてあります。
{ testers }:
testers.runNixOSTest {
  name = "caddy";

  node.specialArgs.hardening = import ../../lib/systemd-hardening.nix;

  containers.machine =
    { pkgs, ... }:
    {
      imports = [ ./caddy.nix ];
      services.caddy.enable = true;
      environment.systemPackages = [ pkgs.curl ];
    };

  testScript = # python
    ''
      machine.wait_for_unit("caddy.service")

      # admin APIをUNIXソケットへ移せているかを確認します。
      # 設定が外れてもCaddyは既定の`localhost:2019`で普通に起動してしまうので、
      # 他のテストは全て通ったまま無言で退行します。
      # 既定に合わせて名前で叩くので、curlは`::1`と`127.0.0.1`の両方を試します。
      with subtest("admin APIはUNIXソケットだけで待ち受ける"):
          machine.succeed("test -S /run/caddy/admin.sock")
          machine.fail("curl --fail --silent --max-time 3 http://localhost:2019/config/")

      # 死活監視用のエンドポイントを確認します。
      # 監視エージェントがここを叩いているので、
      # パスやポートが変わると監視だけが静かに落ちます。
      # `::1`に限定できているかも合わせて見ます。
      with subtest("死活監視用のエンドポイント"):
          machine.wait_for_open_port(2020, "::1")
          machine.succeed("curl --fail --silent --max-time 3 http://[::1]:2020/health")
          machine.fail("curl --fail --silent --max-time 3 http://127.0.0.1:2020/health")
    '';
}
