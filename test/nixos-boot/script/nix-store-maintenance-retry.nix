# ストアの手入れの再試行が、意図した時にだけ起きて、決まった回数で打ち切られることを確認します。
# テスト用のサービスは`../vm/nix-store-maintenance-retry.nix`にあります。
#
# 打ち切りは`ExecCondition`で`NRestarts`を比べる仕組みです。
# 効かなければGCが起動し直し続け、
# `NRestarts`の数え方が想定と違えば、検査の回数がずれたり初回から見送られたりします。
# 前処理が必ず失敗するサービスを起動して、以下を見ます。
#
# - 前処理が動く回数が、上限の5回ちょうどである
# - 打ち切られた時に、失敗ではなく見送りで終わる
#
# 本体の失敗は`RestartPreventExitStatus`で再試行から外しています。
# 効かなければ、全ホストのビルドのような重い本体が失敗のたびに繰り返されます。
# 前処理は成功して本体が失敗するサービスを起動して、以下を見ます。
#
# - 前処理が動くのは1回だけである
# - 起動し直されずに、失敗で終わる
#
# どれが崩れても評価とブートは通ります。
#
# `NRestarts`は見送りで終わると0に戻るので、
# 回数はサービスが書き残したファイルの行数で数えます。
_:
let
  retryUnit = "nix-store-maintenance-retry-test.service";
  retryAttempts = "/run/nix-store-maintenance-retry-test/attempts";
  mainFailureUnit = "nix-store-maintenance-main-failure-test.service";
  mainFailureAttempts = "/run/nix-store-maintenance-main-failure-test/attempts";
in
# python
''
  def wait_until_stopped(unit):
      # 起動し直す合間は`activating`なので、止まったままになるのは終わった時だけです。
      # 失敗で止まった時も待ち終えて、後の検査で分かりやすく落とします。
      machine.wait_until_succeeds(
          f"systemctl show --property=ActiveState --value {unit} | grep --line-regexp --extended-regexp 'inactive|failed'",
          timeout=60,
      )
      # 再試行が止まっていなければ、この後も起動し直して回数が増えます。
      machine.sleep(3)

  def unit_property(unit, name):
      return machine.succeed(f"systemctl show --property={name} --value {unit}").strip()

  machine.succeed("systemctl start --no-block ${retryUnit}")
  wait_until_stopped("${retryUnit}")
  retry_attempts = int(machine.succeed("wc --lines < ${retryAttempts}").strip())
  assert retry_attempts == 5, retry_attempts
  # 失敗で終わった時は`failed`になります。
  retry_state = unit_property("${retryUnit}", "ActiveState")
  assert retry_state == "inactive", retry_state

  machine.succeed("systemctl start --no-block ${mainFailureUnit}")
  wait_until_stopped("${mainFailureUnit}")
  main_failure_attempts = int(machine.succeed("wc --lines < ${mainFailureAttempts}").strip())
  assert main_failure_attempts == 1, main_failure_attempts
  main_failure_state = unit_property("${mainFailureUnit}", "ActiveState")
  assert main_failure_state == "failed", main_failure_state
  main_failure_restarts = unit_property("${mainFailureUnit}", "NRestarts")
  assert main_failure_restarts == "0", main_failure_restarts
''
