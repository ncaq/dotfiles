# `container-socket-activation.nix`が作るproxyを確認します。
#
# 待ち受けは、IPv6のloopbackに加えて、
# 既定の接続先を`127.0.0.1`で持つ外部のツールのためにIPv4のloopbackでも意図して残しています。
# 片方が消えても、評価とブートは通ったまま退行します。
#
# 転送先のIPv6アドレスを角括弧で囲まずに書くのは、
# `systemd-socket-proxyd`が角括弧付きの書き方を名前として引いて失敗するからです。
# 直感に反するので、「直す」つもりで囲むと壊れます。
#
# systemd-nspawnのコンテナの中で、
# `container-socket-activation.nix`だけを読み込んでproxyを1つ宣言したマシンを動かします。
# proxyの形は宣言したホストの全てで同じなので、ホストをブートするテストではなくここに置いています。
# 実機の宣言がproxyへ繋がっていることは、ホストをブートするテストで見ています。
# 実行するnix-daemonに要る設定は`nixos/core/nix-daemon.nix`に書いてあります。
#
# 以下を見ます。
#
# - socketがIPv6とIPv4のloopbackの両方で待ち受けていること。
#   接続すると起動の引き金になって中のコンテナが起き上がろうとするので、`ss`で見ます
# - 実際の`ExecStart`が転送先を角括弧無しで書いていること
# - 実際の`ExecStart`をそのまま動かすと、転送先へ中継できること。
#   テストのマシンの中でさらにコンテナを起動することはできないので、
#   転送先のアドレスをloopbackに付けて、そこへ代わりのHTTPサーバを立てます
{ testers }:
let
  # 中継先になるコンテナ側のアドレスとポート。
  targetAddress = "fd00::2";
  targetPort = "8000";
  # 代わりに待ち受けるポートは、実際のsocketのポートと重ならない番号にします。
  checkPort = "47000";
in
testers.runNixOSTest {
  name = "container-socket-activation";

  node.specialArgs.hardening = import ../../lib/systemd-hardening.nix;

  containers.machine =
    { pkgs, ... }:
    {
      imports = [ ./container-socket-activation.nix ];
      containers.demo = {
        privateNetwork = true;
        hostAddress6 = "fd00::1";
        localAddress6 = targetAddress;
        local.socketActivation = {
          label = "Demo";
          port = pkgs.lib.toInt targetPort;
          healthPath = "/";
        };
        config.system.stateVersion = pkgs.lib.trivial.release;
      };
      environment.systemPackages = [
        pkgs.curl
        pkgs.python3
      ];
    };

  testScript = # python
    ''
      machine.wait_for_unit("sockets.target")

      with subtest("両方のloopbackで待ち受ける"):
          for stream in ["[::1]:${targetPort}", "127.0.0.1:${targetPort}"]:
              machine.wait_until_succeeds(f"ss -Hltn | grep -qF ' {stream} '")

      with subtest("転送先を角括弧無しで書く"):
          exec_starts = [
              line.split("=", 1)[1].strip()
              for line in machine.succeed("systemctl cat demo-proxy.service").splitlines()
              if line.startswith("ExecStart=")
          ]
          assert len(exec_starts) == 1, exec_starts
          exec_start = exec_starts[0]
          assert exec_start.endswith(" ${targetAddress}:${targetPort}"), exec_start

      with subtest("転送先へ中継する"):
          machine.succeed("ip -6 addr add ${targetAddress}/128 dev lo nodad")
          machine.succeed("mkdir -p /tmp/demo && echo ok > /tmp/demo/index.html")
          machine.succeed(
              "systemd-run --unit=demo-check-target"
              " python3 -m http.server --bind ${targetAddress} --directory /tmp/demo ${targetPort}"
          )
          machine.wait_until_succeeds(
              "curl --fail --silent --max-time 3 'http://[${targetAddress}]:${targetPort}/'"
          )
          machine.succeed(
              "systemd-run --unit=demo-check-proxy"
              f" systemd-socket-activate --listen='[::1]:${checkPort}' {exec_start}"
          )
          relayed = machine.wait_until_succeeds(
              "curl --fail --silent --max-time 3 'http://[::1]:${checkPort}/'"
          )
          assert relayed.strip() == "ok", relayed
    '';
}
