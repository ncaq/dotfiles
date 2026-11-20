# ストアの手入れの再試行と打ち切り(`nixos/core/nix-store-maintenance.nix`)を、
# テストVMの中で実際に動かして確かめるためのサービス。
# 確かめる側は`../script/nix-store-maintenance-retry.nix`です。
#
# 本物のGCは負荷が高い時にしか再試行しないので、テストVMでは再試行が起きません。
# 同じ`retryServiceConfig`を使い、前処理が必ず失敗するサービスを用意して、
# 再試行が決まった回数で打ち切られることを見ます。
{
  pkgs,
  lib,
  config,
  ...
}:
let
  name = "nix-store-maintenance-retry-test";
in
{
  systemd.services.${name} = {
    description = "Exercise the retry limit of the Nix store maintenance";
    # 短い間隔で起動し直すので、起動の回数の制限に掛からないようにします。
    # 掛かると打ち切りより先に失敗で止まります。
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig =
      # 待ち時間を伸ばす指定は、下で間隔を固定するので外します。
      removeAttrs config.local.nixStoreMaintenance.retryServiceConfig [ "RestartMaxDelaySec" ] // {
        Type = "oneshot";
        RuntimeDirectory = name;
        # サービスが止まるたびに消されると回数を数えられないので残します。
        RuntimeDirectoryPreserve = true;
        # 負荷の検査の代わりに、動いた回数を書き残して必ず失敗します。
        ExecStartPre = [
          (pkgs.writeShellScript "${name}-pre" ''
            echo attempt >>"$RUNTIME_DIRECTORY/attempts"
            exit 1
          '')
        ];
        ExecStart = lib.getExe' pkgs.coreutils "true";
        # テストを待たせないように、待ち時間は伸ばさずに1秒にします。
        RestartSec = "1s";
        RestartSteps = 0;
      };
  };
}
