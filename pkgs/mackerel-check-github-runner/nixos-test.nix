# ランナのVMのチェックが、VMが止まっている理由がある時にだけ、応答が無くても正常を返すことを確認します。
#
# 正常にする条件が広がりすぎると、VMが落ちても通知されなくなります。
# 狭すぎると、GCのたびに毎日通知が来ます。
# どちらに崩れても評価とブートは通ったままです。
#
# systemd-nspawnのコンテナの中で、GCの代わりのサービスを段階ごとに止めながらチェックを実行します。
# ホストをブートするテストではVMが起動せずGCも動かないので、異常を返す側しか見られませんでした。
# 実行するnix-daemonに要る設定は`nixos/core/nix-daemon.nix`に書いてあります。
#
# 応答しないアドレスに対して、以下を見ます。
#
# - GCも最適化も動いていない時は異常
# - GCが負荷の検査(`start-pre`)にいる時は異常。この間はVMを止めていない
# - GCの本体が動いている時は正常
# - GCが終わった後は異常
# - 最適化の本体が動いている時は正常
#
# 応答するアドレスに対しては、GCの状態に関わらず正常を返すことを見ます。
{ testers }:
let
  # 代わりのサービスが、このファイルができるまで段階に留まります。
  preDone = "/run/nix-gc-test-pre-done";
  mainDone = "/run/nix-gc-test-main-done";
  optimiseDone = "/run/nix-optimise-test-done";
  # 文書用のアドレス。経路が無いのでpingはすぐに失敗します。
  unreachable = "2001:db8::1";
in
testers.runNixOSTest {
  name = "mackerel-check-github-runner";

  containers.machine =
    { pkgs, ... }:
    let
      waitFor =
        name: file:
        pkgs.writeShellScript "nix-gc-test-${name}" ''
          while [ ! -e ${file} ]; do
            sleep 0.2
          done
        '';
    in
    {
      # 本物のGCのユニットを定義させずに、同じ名前の代わりのサービスを置きます。
      nix.enable = false;
      environment.systemPackages = [ pkgs.mackerel-check-github-runner ];
      systemd.services.nix-gc = {
        description = "Stand-in for the Nix Garbage Collector";
        serviceConfig = {
          Type = "oneshot";
          ExecStartPre = waitFor "pre" preDone;
          ExecStart = waitFor "main" mainDone;
        };
      };
      systemd.services.nix-optimise = {
        description = "Stand-in for the Nix Store Optimiser";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = waitFor "optimise" optimiseDone;
        };
      };
    };

  testScript = # python
    ''
      def check(address):
          return machine.execute(f"mackerel-check-github-runner 'Test Runner' {address}")

      def wait_for_state(unit, state):
          machine.wait_until_succeeds(
              f"systemctl show --property=SubState --value {unit}"
              f" | grep --line-regexp {state}"
          )

      def wait_for_gc_state(state):
          wait_for_state("nix-gc.service", state)

      machine.wait_for_unit("multi-user.target")

      with subtest("GCが動いていない時は異常"):
          status, output = check("${unreachable}")
          assert status == 2, (status, output)
          assert output.startswith("Test Runner CRITICAL: ping failed: "), output

      with subtest("負荷の検査の間は異常"):
          machine.succeed("systemctl start --no-block nix-gc.service")
          wait_for_gc_state("start-pre")
          status, output = check("${unreachable}")
          assert status == 2, (status, output)

      with subtest("GCの本体が動いている間は正常"):
          machine.succeed("touch ${preDone}")
          wait_for_gc_state("start")
          status, output = check("${unreachable}")
          assert status == 0, (status, output)
          assert output == "Test Runner OK: stopped while nix-gc.service is start\n", output

      with subtest("応答があれば正常"):
          status, output = check("::1")
          assert status == 0, (status, output)
          assert output == "Test Runner OK: ping succeeded\n", output

      with subtest("GCが終わった後は異常"):
          machine.succeed("touch ${mainDone}")
          wait_for_gc_state("dead")
          status, output = check("${unreachable}")
          assert status == 2, (status, output)

      with subtest("最適化の本体が動いている間は正常"):
          machine.succeed("systemctl start --no-block nix-optimise.service")
          wait_for_state("nix-optimise.service", "start")
          status, output = check("${unreachable}")
          assert status == 0, (status, output)
          assert output == "Test Runner OK: stopped while nix-optimise.service is start\n", output
          machine.succeed("touch ${optimiseDone}")
    '';
}
