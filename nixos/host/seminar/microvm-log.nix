# 全てのmicroVMの中のjournalをコンソールへ流します。
# 理由は`lib/journal-to-console.nix`に、
# 読み方は`nixos/native-linux/machine-log.nix`に書いています。
#
# コンテナの分と別のファイルにしているのは、
# `microvm.vms`のオプションがmicroVMのホストモジュールを取り込んだホストにしか無いためです。
{ lib, ... }:
{
  options.microvm.vms = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        config.extraModules = [ (import ../../../lib/journal-to-console.nix) ];
      }
    );
  };
}
