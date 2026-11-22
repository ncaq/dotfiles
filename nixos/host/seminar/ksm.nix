# KSMを有効にするユニットのハードニング。
#
# KSM自体はmicroVMのホストモジュールが既定で有効にする。
# ユニットは`/sys/kernel/mm/ksm/run`へ1を書き込むだけのoneshotなので、
# それ以外を閉じる。
{
  lib,
  config,
  hardening,
  ...
}:
{
  config = lib.mkIf config.hardware.ksm.enable {
    # /sysへの書き込みが必要なのでProtectKernelTunablesは設定できない。
    systemd.services.enable-ksm.serviceConfig = removeAttrs hardening.isolated [
      "ProtectKernelTunables"
    ];
  };
}
