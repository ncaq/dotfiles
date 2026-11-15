# GitHub ActionsのランナーのVMが、自分で電源を切った後に作り直されることの前提を確認します。
# ランナーのVMは秘密情報が無いとテストVMでは起動しないので、
# 評価とブートが通っても、
# ここが壊れたことには気付けません。
#
# VMは起動から1日経つと、ジョブが無い時に自分で電源を切ります。
# 作り直されるには、以下の2つが要ります。
#
# - ホストの`microvm@`が、正常に終了したVMも起動し直す
# - 起動し直す時に、ストアを準備するサービスも動く
#
# 前者が崩れると、VMは止まったまま戻らず、ランナーが黙って居なくなります。
# 後者が崩れると、書き込み用の層が作り直されずにディスク不足に戻ります。
# `Restart`はmicrovm.nixのテンプレートのユニットの設定なので、
# 評価時の値ではなく`systemctl show`で読みます。
#
# `nixos/host/seminar/github-runner`をimportしていないホストにはオプション自体が生えないので、
# `or`で無いものとして扱います。
{ lib, config, ... }:
let
  githubRunnerVms = config.local.githubRunnerVms or { };
in
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
