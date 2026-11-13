# 全てのmicroVMの中のjournalをコンソールへ流します。
# 理由は`lib/journal-to-console.nix`に、
# 読み方は`nixos/native-linux/machine-log.nix`に書いています。
#
# コンテナの分と別のファイルにしているのは、
# `microvm.vms`のオプションがmicroVMのホストモジュールを取り込んだホストにしか無いためです。
{ lib, ... }:
let
  # microVMのコンソールをシリアル(ttyS0)からvirtio-console(hvc0)へ移します。
  #
  # microvm.nixのcloud-hypervisorの既定は`--serial tty --console null`で、
  # コンソールはエミュレートされた8250 UARTです。
  # 1バイト書くごとにVMMへ抜けるので遅く、
  # journaldはコンソールへ同期的に書くため、
  # ログの多いランナーのVMではjournaldの取り込みが詰まってジョブを遅らせかねません。
  # virtio-consoleはまとめて渡せるので、その負担が小さくなります。
  #
  # cloud-hypervisorは標準入出力へ繋ぐ`tty`をシリアルとコンソールのどちらか一方にしか使えないので、
  # シリアルは切ります。
  # microvm.nixは`--serial`を渡されると`console=ttyS0`を付けなくなるので、
  # `console=hvc0`を自分で渡して`/dev/console`がhvc0を指すようにします。
  #
  # 代わりに、virtio-consoleのドライバが載る前のカーネルの出力はホストに出なくなります。
  # 載った後は溜まっていた分もまとめて出るので、
  # 失うのはドライバが載る前にカーネルが止まった時の出力だけです。
  virtioConsole = {
    microvm.cloud-hypervisor.extraArgs = [
      "--console"
      "tty"
      "--serial"
      "off"
    ];
    boot.kernelParams = [ "console=hvc0" ];
  };
in
{
  options.microvm.vms = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        config.extraModules = [
          (import ../../../lib/journal-to-console.nix)
          virtioConsole
        ];
      }
    );
  };
}
