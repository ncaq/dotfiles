# GitHub ActionsのランナーのVMのために、ホスト側で用意するものを確認します。
# ランナーのVMは秘密情報が無いとテストVMでは起動しないので、
# 評価とブートが通っても以下は静かに壊れます。
#
# - ストアの準備のサービスが、前の書き込み用の層のイメージを消して、
#   ホストのNixのデータベースの写しを壊れていない形で置くこと。
#   ここが失敗するとVMが起動できなくなります
# - ホストのGCの前後の処理に、全てのランナーのVMのユニットが入っていること。
#   GCがパスを消した後もVMが動き続けると、VMのデータベースと実体が食い違います
#
# `nixos/host/seminar/github-runner`をimportしていないホストにはオプション自体が生えないので、
# `or`で無いものとして扱います。
{
  lib,
  pkgs,
  config,
  ...
}:
let
  githubRunnerVms = config.local.githubRunnerVms or { };
  sqlite3 = lib.getExe pkgs.sqlite;
in
lib.concatStrings (
  lib.mapAttrsToList (
    name: vm: # python
    ''
      machine.succeed("systemctl start install-microvm-${name}.service")
      machine.succeed("touch ${vm.overlayImage}")
      machine.succeed("systemctl start ${vm.storeService}")
      machine.fail("test -e ${vm.overlayImage}")
      store_database_check = machine.succeed(
          "${sqlite3} ${vm.storeDatabase} 'PRAGMA integrity_check'"
      )
      assert store_database_check.strip() == "ok", store_database_check
    '') githubRunnerVms
)
+ lib.optionalString (githubRunnerVms != { }) (
  # python
  ''
    nix_gc_unit = machine.succeed("systemctl cat nix-gc.service")
    for key in ["ExecStartPre", "ExecStopPost"]:
        nix_gc_scripts = [
            line.split("=", 1)[1].strip()
            for line in nix_gc_unit.splitlines()
            if line.startswith(key + "=")
        ]
        assert len(nix_gc_scripts) == 1, nix_gc_unit
        nix_gc_script = machine.succeed(f"cat {nix_gc_scripts[0]}")
  ''
  + lib.concatMapStrings (
    name: # python
    ''
      ${"    "}assert "microvm@${name}.service" in nix_gc_script, nix_gc_script
    '') (lib.attrNames githubRunnerVms)
)
