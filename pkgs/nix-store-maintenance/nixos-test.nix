# ストアのGCと最適化の起動の流れ(`module.nix`)が、意図した形に組み上がっていて、
# 再試行が意図した時にだけ起きて、決まった回数で打ち切られることを確認します。
# どれが崩れても評価とブートは通り、
# GCが動かなくなったり、起動の直後に動いたり、起動し直し続けたりするだけなので、気付きにくいです。
#
# systemd-nspawnのコンテナの中で`module.nix`の実際のユニットを読み込んで確かめます。
# ホストの構成には依らないので、ホストをブートするテストではなくここに置いています。
# 実行するnix-daemonに要る設定は`nixos/core/nix-daemon.nix`に書いてあります。
#
# # 起動の流れ
#
# - GCのタイマーが起動の時には有効にならず、起動からの時間で動くタイマーに任されていること
# - GCが負荷の検査を前処理の先頭に持ち、再試行と打ち切りの設定が入っていること
# - タイマーを持たない最適化のサービスが、GCから起動できるように定義されていること
# - GCのタイマーが起動するのがGCであること。
#   GCの前に別の処理を挟むホストの流れは、挟む側(`pkgs/nix-gc-root-hosts`)のテストで見ます
#
# # 再試行と打ち切り
#
# 本物のGCは負荷が高い時にしか再試行しないので、テストでは再試行が起きません。
# 同じ`retryServiceConfig`を使うサービスを2つ用意して、両方の側を見ます。
#
# 打ち切りは`ExecCondition`で`NRestarts`を比べる仕組みです。
# 効かなければGCが起動し直し続け、
# `NRestarts`の数え方が想定と違えば、検査の回数がずれたり初回から見送られたりします。
# 前処理が必ず失敗するサービスを起動して、以下を見ます。
#
# - 前処理が動く回数が、上限の回数ちょうどである
# - 打ち切られた時に、失敗ではなく見送りで終わる
#
# 本体の失敗は`RestartPreventExitStatus`で再試行から外しています。
# 効かなければ、全ホストのビルドのような重い本体が失敗のたびに繰り返されます。
# 前処理は成功して本体が失敗するサービスを起動して、以下を見ます。
#
# - 前処理が動くのは1回だけである
# - 起動し直されずに、失敗で終わる
#
# `NRestarts`は見送りで終わると0に戻るので、
# 回数はサービスが書き残したファイルの行数で数えます。
{
  lib,
  testers,
  maxAttempts,
}:
let
  retryTests = {
    # 前処理が必ず失敗するサービス。
    retry = {
      name = "nix-store-maintenance-retry-test";
      description = "Exercise the retry limit of the Nix store maintenance";
      preExit = 1;
      mainExit = 0;
    };
    # 前処理は成功して本体が失敗するサービス。
    mainFailure = {
      name = "nix-store-maintenance-main-failure-test";
      description = "Exercise a main process failure of the Nix store maintenance";
      preExit = 0;
      mainExit = 1;
    };
  };
  attemptsOf = test: "/run/${test.name}/attempts";
in
testers.runNixOSTest {
  name = "nix-store-maintenance";

  containers.machine =
    { pkgs, config, ... }:
    let
      mkRetryTest = test: {
        inherit (test) description;
        # 短い間隔で起動し直すので、起動の回数の制限に掛からないようにします。
        # 掛かると打ち切りより先に失敗で止まります。
        unitConfig.StartLimitIntervalSec = 0;
        serviceConfig =
          # 待ち時間を伸ばす指定は、下で間隔を固定するので外します。
          removeAttrs config.local.nixStoreMaintenance.retryServiceConfig [ "RestartMaxDelaySec" ] // {
            Type = "oneshot";
            RuntimeDirectory = test.name;
            # サービスが止まるたびに消されると回数を数えられないので残します。
            RuntimeDirectoryPreserve = true;
            # 負荷の検査の代わりに、動いた回数を書き残します。
            ExecStartPre = [
              (pkgs.writeShellScript "${test.name}-pre" ''
                echo attempt >>"$RUNTIME_DIRECTORY/attempts"
                exit ${toString test.preExit}
              '')
            ];
            ExecStart = pkgs.writeShellScript "${test.name}-main" ''
              exit ${toString test.mainExit}
            '';
            # テストを待たせないように、待ち時間は伸ばさずに1秒にします。
            RestartSec = "1s";
            RestartSteps = 0;
          };
      };
    in
    {
      imports = [ ./module.nix ];
      systemd.services = lib.mapAttrs' (
        _: test: lib.nameValuePair test.name (mkRetryTest test)
      ) retryTests;
    };

  testScript = # python
    ''
      def unit_lines(unit, key):
          text = machine.succeed(f"systemctl cat {unit}")
          return [
              line.split("=", 1)[1].strip()
              for line in text.splitlines()
              if line.startswith(key + "=")
          ]

      def unit_property(unit, name):
          return machine.succeed(f"systemctl show --property={name} --value {unit}").strip()

      def wait_until_stopped(unit):
          # 起動し直す合間は`activating`なので、止まったままになるのは終わった時だけです。
          # 失敗で止まった時も待ち終えて、後の検査で分かりやすく落とします。
          machine.wait_until_succeeds(
              f"systemctl show --property=ActiveState --value {unit} | grep --line-regexp --extended-regexp 'inactive|failed'",
              timeout=60,
          )
          # 再試行が止まっていなければ、この後も起動し直して回数が増えます。
          machine.sleep(3)

      machine.wait_for_unit("multi-user.target")

      with subtest("起動の流れ"):
          gc_timer_wanted_by = unit_property("nix-gc.timer", "WantedBy")
          assert gc_timer_wanted_by == "", gc_timer_wanted_by
          machine.succeed("systemctl is-active nix-gc-after-boot.timer")
          after_boot_unit = unit_property("nix-gc-after-boot.timer", "Unit")
          assert after_boot_unit == "nix-gc.timer", after_boot_unit

          gc_start_pre = unit_lines("nix-gc.service", "ExecStartPre")
          assert gc_start_pre, gc_start_pre
          assert "nix-store-maintenance-condition" in gc_start_pre[0], gc_start_pre
          gc_condition = unit_lines("nix-gc.service", "ExecCondition")
          assert len(gc_condition) == 1, gc_condition
          assert "nix-store-maintenance-retry-limit" in gc_condition[0], gc_condition
          assert unit_lines("nix-gc.service", "Restart") == ["on-failure"]
          assert unit_lines("nix-gc.service", "RestartSteps") == ["3"]
          # 本体の失敗とタイムアウトを再試行から外す指定。
          # systemdが読み取った後の値で見ます。シグナルは`SIG`を除いた名前で返ります。
          gc_restart_prevent = unit_property("nix-gc.service", "RestartPreventExitStatus").split()
          for expected in ["1", "255", "TERM", "KILL"]:
              assert expected in gc_restart_prevent, (expected, gc_restart_prevent)

          machine.succeed("systemctl cat nix-optimise.service")

          gc_timer_unit = unit_property("nix-gc.timer", "Unit")
          assert gc_timer_unit == "nix-gc.service", gc_timer_unit

      with subtest("再試行の打ち切り"):
          machine.succeed("systemctl start --no-block ${retryTests.retry.name}.service")
          wait_until_stopped("${retryTests.retry.name}.service")
          retry_attempts = int(machine.succeed("wc --lines < ${attemptsOf retryTests.retry}").strip())
          assert retry_attempts == ${toString maxAttempts}, retry_attempts
          # 失敗で終わった時は`failed`になります。
          retry_state = unit_property("${retryTests.retry.name}.service", "ActiveState")
          assert retry_state == "inactive", retry_state

      with subtest("本体の失敗は再試行しない"):
          machine.succeed("systemctl start --no-block ${retryTests.mainFailure.name}.service")
          wait_until_stopped("${retryTests.mainFailure.name}.service")
          main_failure_attempts = int(
              machine.succeed("wc --lines < ${attemptsOf retryTests.mainFailure}").strip()
          )
          assert main_failure_attempts == 1, main_failure_attempts
          main_failure_state = unit_property("${retryTests.mainFailure.name}.service", "ActiveState")
          assert main_failure_state == "failed", main_failure_state
          main_failure_restarts = unit_property("${retryTests.mainFailure.name}.service", "NRestarts")
          assert main_failure_restarts == "0", main_failure_restarts
    '';
}
