# ストアのGCと最適化の起動の流れ(`nixos/core/nix-store-maintenance.nix`)が、
# 意図した形に組み上がっていることを確認します。
# どれが崩れても評価とブートは通り、
# GCが動かなくなったり、起動の直後に動いたりするだけなので、気付きにくいです。
#
# 以下を見ます。
#
# - GCのタイマーが起動の時には有効にならず、起動からの時間で動くタイマーに任されていること
# - GCが負荷の検査を前処理の先頭に持ち、再試行と打ち切りの設定が入っていること
# - タイマーを持たない最適化のサービスが、GCから起動できるように定義されていること
# - GCのタイマーが起動するユニットが、実機の構成の通りであること
#
# GCの前にGC rootの更新を挟むホストでは、
# タイマーがGC rootの更新を起動して、それが終わった時にGCを起動することも見ます。
{ lib, config, ... }:
let
  rootHostsUnit = "nix-gc-root-hosts.service";
  hasRootHosts = config.systemd.services ? nix-gc-root-hosts;
  timerUnit = if hasRootHosts then rootHostsUnit else "nix-gc.service";
in
# python
''
  def unit_lines(unit, key):
      text = machine.succeed(f"systemctl cat {unit}")
      return [
          line.split("=", 1)[1].strip()
          for line in text.splitlines()
          if line.startswith(key + "=")
      ]

  gc_timer_wanted_by = machine.succeed(
      "systemctl show nix-gc.timer --property=WantedBy --value"
  ).strip()
  assert gc_timer_wanted_by == "", gc_timer_wanted_by
  machine.succeed("systemctl is-active nix-gc-after-boot.timer")
  after_boot_unit = machine.succeed(
      "systemctl show nix-gc-after-boot.timer --property=Unit --value"
  ).strip()
  assert after_boot_unit == "nix-gc.timer", after_boot_unit

  gc_start_pre = unit_lines("nix-gc.service", "ExecStartPre")
  assert gc_start_pre, gc_start_pre
  assert "nix-store-maintenance-condition" in gc_start_pre[0], gc_start_pre
  gc_condition = unit_lines("nix-gc.service", "ExecCondition")
  assert len(gc_condition) == 1, gc_condition
  assert "nix-store-maintenance-retry-limit" in gc_condition[0], gc_condition
  assert unit_lines("nix-gc.service", "Restart") == ["on-failure"]
  assert unit_lines("nix-gc.service", "RestartSteps") == ["3"]
  assert unit_lines("nix-gc.service", "RestartPreventExitStatus"), "RestartPreventExitStatus"

  machine.succeed("systemctl cat nix-optimise.service")

  gc_timer_unit = machine.succeed(
      "systemctl show nix-gc.timer --property=Unit --value"
  ).strip()
  assert gc_timer_unit == ${builtins.toJSON timerUnit}, gc_timer_unit
''
+ lib.optionalString hasRootHosts ''
  root_hosts_start_post = unit_lines(${builtins.toJSON rootHostsUnit}, "ExecStartPost")
  assert len(root_hosts_start_post) == 1, root_hosts_start_post
  assert root_hosts_start_post[0].endswith(
      "start --no-block nix-gc.service"
  ), root_hosts_start_post
''
