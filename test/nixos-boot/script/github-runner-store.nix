# GitHub ActionsのランナーのVMのストアをホスト側で準備するサービスを確認します。
# ランナーのVMは秘密情報が無いとテストVMでは起動しないので、
# 評価とブートが通っても、
# ここが壊れたことには気付けません。
#
# 準備のサービスが、前の書き込み用の層のイメージを消して、
# ホストのNixのデータベースの写しを壊れていない形で置くことを見ます。
# ここが失敗するとVMが起動できなくなります。
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
