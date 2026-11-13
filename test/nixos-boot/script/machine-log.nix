# コンテナとmicroVMの中のjournalがホストのjournalへ届いていて、
# `machine-log`(`nixos/native-linux/machine-log.nix`)で読めることを確認します。
# ゲストのjournaldの設定が外れても、評価とブートは通ったまま、
# ブートの表示だけが入る元の状態へ静かに戻ります。
# 障害が起きて読もうとした時に初めて気付くことになります。
{
  lib,
  config,
  startsInTestVm,
  ...
}:
let
  microvms = config.microvm.vms or { };

  # 全てのコンテナとmicroVMに、ログを流す設定が入っていることを評価の結果で確認します。
  # テストVMの中で実際のログを見られるのはテストVMで起動するマシンだけです。
  # 設定は`options.containers`と`options.microvm.vms`のsubmoduleへ足した定義が、
  # 各マシンの定義と合成されることで入るので、
  # 合成が崩れても起動しないマシンでは評価もブートも通ってしまいます。
  # GitHub ActionsのランナーのVMがちょうど起動しないマシンです。
  #
  # 以下を見ます。
  #
  # - 全てのコンテナとmicroVMの中で、journaldがコンソールへ書く設定になっていること
  # - 全てのmicroVMのホスト側のユニットが、VMと同じ名前のjournalのnamespaceへログを出すこと
  guestConfigs =
    lib.mapAttrs (_: c: c.config) config.containers // lib.mapAttrs (_: vm: vm.config.config) microvms;
  withoutConsole = lib.attrNames (
    lib.filterAttrs (_: guest: guest.services.journald.console == "") guestConfigs
  );
  withoutNamespace = lib.filter (
    name: (config.systemd.services."microvm@${name}".serviceConfig.LogNamespace or null) != name
  ) (lib.attrNames microvms);

  # ブートの表示(`[  OK  ] Started ...`)はjournaldを通らずに出るので、
  # journaldが流した行にだけ現れる`systemd[1]: `の形を探します。
  #
  # テストVMでも起動するマシンだけを見ます。
  # microVMは`startsInTestVm`のもの、
  # コンテナは`postgres-extension.nix`が拡張を確かめているpostgresqlです。
  #
  # microVMの行がホストの既定のjournalには入っていないことも見ます。
  # VMごとのjournalのnamespaceへ分けているのは、
  # VMが大量に書いてホスト自身のログを押し出せないようにするためで、
  # 分け方が外れてもログは既定のjournalへ入って読めてしまうので気付けません。
  vmNames = lib.filter startsInTestVm (lib.attrNames microvms);
  containerNames = lib.optional (config.containers ? postgresql) "postgresql";

  # `machine-log`のコマンド自体の分岐を確かめるための、
  # 起動しないマシンも含めた全てのマシンの名前です。
  # 引数無しの一覧がこの名前を1行ずつ出すことと、
  # 知らない名前は失敗することを見ます。
  # 名前の対応はNixの評価時に`case`文として生成しているので、
  # 生成の仕方が崩れると全ての名前が知らない名前の側へ落ちます。
  allNames = lib.attrNames config.containers ++ lib.attrNames microvms;
in
assert lib.assertMsg (
  withoutConsole == [ ]
) "中のjournalをコンソールへ流す設定が入っていないマシンがあります: ${lib.concatStringsSep ", " withoutConsole}";
assert lib.assertMsg (
  withoutNamespace == [ ]
) "ログをjournalのnamespaceへ分けていないmicroVMがあります: ${lib.concatStringsSep ", " withoutNamespace}";
lib.optionalString (allNames != [ ]) # python
  ''
    machine_log_list = machine.succeed("machine-log").splitlines()
    assert sorted(machine_log_list) == sorted(${builtins.toJSON allNames}), machine_log_list
    machine.fail("machine-log no-such-machine")
  ''
+ lib.concatMapStrings (
  name: # python
  ''
    machine.wait_until_succeeds(
        "machine-log ${name} --no-pager --output=cat | grep -F 'systemd[1]: '"
    )
  '') (vmNames ++ containerNames)
+ lib.concatMapStrings (
  name: # python
  ''
    machine.fail(
        "journalctl --unit=microvm@${name}.service --no-pager --output=cat"
        " | grep -F 'systemd[1]: '"
    )
  '') vmNames
