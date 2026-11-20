# ストアの手入れの再試行と打ち切り(`nixos/core/nix-store-maintenance.nix`)を、
# テストVMの中で実際に動かして確かめるためのサービス。
# 確かめる側は`../script/nix-store-maintenance-retry.nix`です。
#
# 本物のGCは負荷が高い時にしか再試行しないので、テストVMでは再試行が起きません。
# 同じ`retryServiceConfig`を使うサービスを2つ用意して、両方の側を見ます。
#
# - 前処理が必ず失敗するサービス。再試行が決まった回数で打ち切られることを見ます
# - 前処理は成功して本体が失敗するサービス。本体の失敗では再試行されないことを見ます
{
  pkgs,
  lib,
  config,
  ...
}:
let
  mkRetryTest =
    {
      name,
      description,
      # 前処理の終了コード。
      preExit,
      # 本体の終了コード。
      mainExit,
    }:
    {
      inherit description;
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
          # 負荷の検査の代わりに、動いた回数を書き残します。
          ExecStartPre = [
            (pkgs.writeShellScript "${name}-pre" ''
              echo attempt >>"$RUNTIME_DIRECTORY/attempts"
              exit ${toString preExit}
            '')
          ];
          ExecStart = pkgs.writeShellScript "${name}-main" ''
            exit ${toString mainExit}
          '';
          # テストを待たせないように、待ち時間は伸ばさずに1秒にします。
          RestartSec = "1s";
          RestartSteps = 0;
        };
    };
  tests = [
    {
      name = "nix-store-maintenance-retry-test";
      description = "Exercise the retry limit of the Nix store maintenance";
      preExit = 1;
      mainExit = 0;
    }
    {
      name = "nix-store-maintenance-main-failure-test";
      description = "Exercise a main process failure of the Nix store maintenance";
      preExit = 0;
      mainExit = 1;
    }
  ];
in
{
  systemd.services = lib.listToAttrs (
    map (test: lib.nameValuePair test.name (mkRetryTest test)) tests
  );
}
