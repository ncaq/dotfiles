# GitHub ActionsのランナのVMへ渡すストアの状態を、VMの起動のたびに作り直すNixOSモジュール。
#
# VMごとに`<VMの名前>-store.service`を定義します。
# `RemainAfterExit`を付けないので、VMのユニットが`Requires`していれば、
# VMが起動し直されるたびにもう一度動きます。
# ここが失敗するとVMが起動できなくなります。
#
# ユニットの権限の絞り込みは、コマンドが何を読み書きするかと対になっているので、パッケージの隣に置いています。
# 使う側(`nixos/host/seminar/github-runner/github-runner-x64.nix`)は、
# イメージの場所を渡して、VMのユニットとの依存を足します。
# テスト(`nixos-test.nix`)もこのモジュールだけを読むので、ホストの構成に依存しません。
{
  pkgs,
  lib,
  config,
  hardening,
  ...
}:
let
  cfg = config.services.github-runner-store;
in
{
  options.services.github-runner-store = {
    nixDbDir = lib.mkOption {
      type = lib.types.path;
      default = "/nix/var/nix/db";
      description = "写しを取る元の、ホストのNixのデータベースのディレクトリ。";
    };
    vms = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, config, ... }:
          {
            options = {
              overlayImage = lib.mkOption {
                type = lib.types.path;
                description = "VMだけが持つ書き込み用の層のイメージ。起動のたびに消す。";
              };
              unit = lib.mkOption {
                type = lib.types.str;
                readOnly = true;
                default = "${name}-store";
                description = "ストアの状態を作り直すサービスの、`.service`を除いた名前。";
              };
              storeDir = lib.mkOption {
                type = lib.types.path;
                readOnly = true;
                # サービスの`CacheDirectory`として作られます。
                # 写しは数百MiBあるので、tmpfsの`/run`ではなくディスクに置いてホストのメモリを使わせません。
                default = "/var/cache/${config.unit}";
                description = "ホストのNixのデータベースの写しを置くディレクトリ。VMへ共有する。";
              };
              database = lib.mkOption {
                type = lib.types.path;
                readOnly = true;
                default = "${config.storeDir}/db.sqlite";
                description = "ホストのNixのデータベースの写し。";
              };
            };
          }
        )
      );
      default = { };
      description = "ストアの状態を作り直す対象のVM。属性名はVMの名前。";
    };
  };

  config.systemd.services = lib.mapAttrs' (
    name: vm:
    lib.nameValuePair vm.unit {
      description = "Prepare Nix store for ${name}";
      serviceConfig = hardening.isolated // {
        Type = "oneshot";
        ExecStart = lib.escapeShellArgs [
          (lib.getExe pkgs.github-runner-store)
          cfg.nixDbDir
          vm.storeDir
          vm.overlayImage
        ];
        CacheDirectory = vm.unit;
        CacheDirectoryMode = "0700";
        # WALモードのデータベースは読むだけでも共有メモリのファイルへ書き込みます。
        ReadWritePaths = [
          cfg.nixDbDir
          (dirOf vm.overlayImage)
        ];
        # イメージとその親のディレクトリはVMを動かすユーザの所有なので、
        # rootでも所有者の検査を越える権限が無いと消せません。
        CapabilityBoundingSet = [ "CAP_DAC_OVERRIDE" ];
      };
    }
  ) cfg.vms;
}
