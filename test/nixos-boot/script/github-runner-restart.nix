# GitHub ActionsのランナのVMが、止まった後に作り直されることの前提を確認します。
# ランナのVMは秘密情報が無いとテストVMでは起動しないので、
# 評価とブートが通っても、
# ここが壊れたことには気付けません。
#
# VMの書き込み用の層は、VMを再起動すると空になります。
# VMはホストのGCと最適化に毎日再起動されるほか、
# ジョブがVMの中で電源を切った時や、異常終了した時にも止まります。
# 作り直されるには、以下の2つが要ります。
#
# - 起動し直す時に、ストアを準備するサービスも動く。
#   どの場合にも要ります
# - ホストの`microvm@`が、正常に終了したVMも起動し直す。
#   要るのは、ジョブがVMの中で電源を切った時と、異常終了した時です。
#   ホストのGCと最適化は、後処理がVMを明示的に起動します
#
# 前者が崩れると、書き込み用の層が作り直されずに増え続けて、ディスク不足になります。
# 後者が崩れると、VMは止まったまま戻らず、ランナが黙って居なくなります。
# `Restart`はmicrovm.nixのテンプレートのユニットの設定なので、
# 評価時の値ではなく`systemctl show`で読みます。
#
# `nixos/host/seminar/github-runner`をimportしていないホストにはオプション自体が生えないので、
# `or`で無いものとして扱います。
{ lib, config, ... }:
let
  githubRunnerVms = config.local.githubRunnerVms or { };
  # VMの中のランナのサービスが、成功で終わっても失敗で終わっても起動し直されること。
  # 上流のモジュールの既定は成功で終わった時だけで、
  # 失敗で終わるとVMは動いたままランナだけが居なくなります。
  # 起動し直す仕組みの振る舞いは`rerun-with-backoff.test.nix`が確かめるので、
  # ここでは全てのランナのサービスがその対象になっていることだけを見ます。
  # ランナのVMはテストVMでは起動しないので、VMの構成を評価して読みます。
  rerunUnitsOf = name: config.microvm.vms.${name}.config.config.local.rerunWithBackoff;
  runnersRerun = lib.all (
    name:
    lib.all (
      runner: lib.elem "github-runner-${runner}" (rerunUnitsOf name)
    ) githubRunnerVms.${name}.runnerNames
  ) (lib.attrNames githubRunnerVms);
in
assert lib.assertMsg runnersRerun "GitHub Actionsのランナのサービスが起動し直す対象になっていません";
lib.concatStrings (
  lib.mapAttrsToList (
    name: vm: # python
    ''
      vm_restart = machine.succeed(
          "systemctl show microvm@${name}.service --property=Restart --value"
      ).strip()
      assert vm_restart == "always", vm_restart
      vm_requires = machine.succeed(
          "systemctl show microvm@${name}.service --property=Requires --value"
      ).split()
      assert "${vm.storeService}" in vm_requires, vm_requires
    '') githubRunnerVms
)
