# MackerelのGitHub ActionsのランナのVMのチェックが、
# VMが止まっている理由が無い時には異常を返すことを確認します。
#
# このチェックは、ホストのGCとストアの最適化がVMを止めている間は、
# 応答が無くても正常を返します。
# 正常にする条件が広がりすぎると、VMが落ちても通知されなくなりますが、
# 評価とブートは通ったままです。
#
# ランナのVMは秘密情報が無いとテストVMでは起動しないので、
# テストVMではpingは必ず失敗します。
# GCも最適化も動いていない時に実行して、終了コードが2になることを見ます。
#
# Mackerelを有効にしていないホストにはチェックの定義が無いので、
# `or`で無いものとして扱います。
{ lib, config, ... }:
let
  checks = config.services.mackerel-agent.settings.plugin.checks or { };
  runnerChecks = lib.filterAttrs (name: _: lib.hasPrefix "github-runner-" name) checks;
in
lib.concatStrings (
  lib.mapAttrsToList (
    name: check: # python
    ''
      for store_unit in ["nix-gc.service", "nix-optimise.service"]:
          store_unit_state = machine.succeed(
              f"systemctl show --property=SubState --value {store_unit}"
          ).strip()
          assert store_unit_state == "dead", (store_unit, store_unit_state)
      status, output = machine.execute(${builtins.toJSON check.command})
      assert status == 2, (${builtins.toJSON name}, status, output)
    '') runnerChecks
)
