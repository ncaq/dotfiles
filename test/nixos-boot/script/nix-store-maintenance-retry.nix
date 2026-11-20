# ストアの手入れの再試行が、決まった回数で打ち切られることを確認します。
#
# 打ち切りは`ExecCondition`で`NRestarts`を比べる仕組みです。
# 効かなければGCが起動し直し続け、
# `NRestarts`の数え方が想定と違えば、検査の回数がずれたり初回から見送られたりします。
# どちらも評価とブートは通ります。
#
# 前処理が必ず失敗するテスト用のサービス(`../vm/nix-store-maintenance-retry.nix`)を起動して、
# 以下を見ます。
#
# - 前処理が動く回数が、上限の5回ちょうどである
# - 打ち切られた時に、失敗ではなく見送りで終わる
#
# `NRestarts`は見送りで終わると0に戻るので、
# 回数はサービスが書き残したファイルの行数で数えます。
_:
let
  unit = "nix-store-maintenance-retry-test.service";
  attempts = "/run/nix-store-maintenance-retry-test/attempts";
in
# python
''
  machine.succeed("systemctl start --no-block ${unit}")
  # 打ち切られて止まるのを待ちます。
  # 起動し直す合間は`activating`なので、`inactive`になるのは打ち切られた時だけです。
  machine.wait_until_succeeds(
      "test \"$(systemctl show --property=ActiveState --value ${unit})\" = inactive"
      " && test -e ${attempts}",
      timeout=60,
  )
  # 打ち切りが効いていなければ、この後も起動し直して回数が増えます。
  machine.sleep(3)
  retry_attempts = int(machine.succeed("wc --lines < ${attempts}").strip())
  assert retry_attempts == 5, retry_attempts
  # 失敗で終わった時は`failed`になります。
  retry_state = machine.succeed(
      "systemctl show --property=ActiveState --value ${unit}"
  ).strip()
  assert retry_state == "inactive", retry_state
''
