# ランナのVMのチェックが、VMが止まっている理由がある時にだけ、ランナが使えなくても正常を返すことを確認します。
#
# 正常にする条件が広がりすぎると、VMが落ちても通知されなくなります。
# 狭すぎると、GCのたびに毎日通知が来ます。
# どちらに崩れても評価とブートは通ったままです。
#
# systemd-nspawnのコンテナの中で、GCの代わりのサービスを段階ごとに止めながらチェックを実行します。
# ホストをブートするテストではVMが起動せずGCも動かないので、異常を返す側しか見られませんでした。
# 実行するnix-daemonに要る設定は`nixos/core/nix-daemon.nix`に書いてあります。
#
# GitHubのAPIの代わりに、コンテナの中でランナの一覧のJSONを返すHTTPサーバを立てます。
# 返すJSONを差し替えて、ランナが登録されていない時に以下を見ます。
#
# - GCも最適化も動いていない時は異常
# - GCが負荷の検査(`start-pre`)にいる時は異常。この間はVMを止めていない
# - GCの本体が動いている時は正常
# - GCが終わった後は異常
# - 最適化の本体が動いている時は正常
#
# ランナがonlineなら、GCの状態に関わらず正常を返すことを見ます。
# ランナがofflineなら、登録されていない時と同じく異常を返すことを見ます。
# APIが失敗を返す時はUNKNOWNを返すことを見ます。
{ testers }:
let
  # 代わりのサービスが、このファイルができるまで段階に留まります。
  preDone = "/run/nix-gc-test-pre-done";
  mainDone = "/run/nix-gc-test-main-done";
  optimiseDone = "/run/nix-optimise-test-done";
  # 代わりのAPIが配るディレクトリと待ち受けるポート。
  apiRoot = "/run/fake-github";
  apiPort = 8000;
  repository = "test/repo";
  runner = "test-0";
  # このファイルの中身がランナの一覧として返ります。
  runnersFile = "${apiRoot}/repos/${repository}/actions/runners";
  tokenFile = "/run/fake-github-token";
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
      # クエリ文字列は無視されるので、名前の絞り込みに関わらず置いたファイルを返します。
      # 置いていないリポジトリは404になります。
      systemd.services.fake-github = {
        description = "Stand-in for the GitHub REST API";
        wantedBy = [ "multi-user.target" ];
        preStart = "mkdir -p ${dirOf runnersFile}";
        serviceConfig.ExecStart = "${pkgs.python3.interpreter} -m http.server --bind ::1 --directory ${apiRoot} ${toString apiPort}";
      };
    };

  testScript = # python
    ''
      import json

      def check(repository="${repository}"):
          return machine.execute(
              "mackerel-check-github-runner --label 'Test Runner'"
              " --api http://[::1]:${toString apiPort}"
              " --token-file ${tokenFile}"
              f" --repository {repository} --runner ${runner}"
          )

      def set_runners(runners):
          body = json.dumps({"total_count": len(runners), "runners": runners})
          machine.succeed(f"echo '{body}' > ${runnersFile}")

      def wait_for_state(unit, state):
          machine.wait_until_succeeds(
              f"systemctl show --property=SubState --value {unit}"
              f" | grep --line-regexp {state}"
          )

      def wait_for_gc_state(state):
          wait_for_state("nix-gc.service", state)

      machine.wait_for_unit("multi-user.target")
      machine.wait_for_open_port(${toString apiPort}, "::1")
      machine.succeed("echo dummy > ${tokenFile}")
      set_runners([])

      with subtest("GCが動いていない時は異常"):
          status, output = check()
          assert status == 2, (status, output)
          assert output == "Test Runner CRITICAL: ${runner} is not registered\n", output

      with subtest("APIが失敗を返す時はUNKNOWN"):
          status, output = check("test/missing")
          assert status == 3, (status, output)
          assert output.startswith("Test Runner UNKNOWN: cannot ask GitHub about ${runner}: 404 "), output

      with subtest("負荷の検査の間は異常"):
          machine.succeed("systemctl start --no-block nix-gc.service")
          wait_for_gc_state("start-pre")
          status, output = check()
          assert status == 2, (status, output)

      with subtest("GCの本体が動いている間は正常"):
          machine.succeed("touch ${preDone}")
          wait_for_gc_state("start")
          status, output = check()
          assert status == 0, (status, output)
          assert output == "Test Runner OK: stopped while nix-gc.service is start\n", output

      with subtest("onlineなら正常"):
          set_runners([{"name": "${runner}", "status": "online"}])
          status, output = check()
          assert status == 0, (status, output)
          assert output == "Test Runner OK: online: ${runner}\n", output

      with subtest("GCが終わった後にofflineなら異常"):
          set_runners([{"name": "${runner}", "status": "offline"}])
          machine.succeed("touch ${mainDone}")
          wait_for_gc_state("dead")
          status, output = check()
          assert status == 2, (status, output)
          assert output == "Test Runner CRITICAL: ${runner} is offline\n", output

      with subtest("最適化の本体が動いている間は正常"):
          set_runners([])
          machine.succeed("systemctl start --no-block nix-optimise.service")
          wait_for_state("nix-optimise.service", "start")
          status, output = check()
          assert status == 0, (status, output)
          assert output == "Test Runner OK: stopped while nix-optimise.service is start\n", output
          machine.succeed("touch ${optimiseDone}")
    '';
}
