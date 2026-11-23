{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.programs.removable-crypt;

  dmNamePattern = "[a-zA-Z0-9][a-zA-Z0-9#+=@_.:-]*";

  deviceIdType = lib.types.strMatching dmNamePattern // {
    description = "device ID under /dev/disk/by-id/ (alphanumeric, #+-.:=@_)";
  };

  deviceType = lib.types.submodule {
    options = {
      deviceId = lib.mkOption {
        type = deviceIdType;
        description = "ID of the device under `/dev/disk/by-id/`";
        example = "usb-JetFlash_Transcend_32GB_25XSK57XTBIHQODC-0:0-part1";
      };
      mountOptions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "noatime" ];
        description = "Mount options to use for all filesystems";
        example = [
          "noatime"
          "nodiratime"
        ];
      };
      btrfsMountOptions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "compress=zstd" ];
        description = "Additional mount options to use when the filesystem is btrfs";
        example = [ "compress=zstd" ];
      };
    };
  };

  # マウントとアンマウントの中身。`pkgs/removable-crypt`にあります。
  removable-crypt = pkgs.removable-crypt.override {
    systemd = config.systemd.package;
  };

  # デバイスごとの`mnt-<名前>`と`umnt-<名前>`。
  # サブコマンドとデバイスごとの引数を付けて包みます。
  mkCommands =
    name: device:
    let
      mountArguments = [
        "mount"
        "--name"
        name
        "--device-id"
        device.deviceId
        # マウントオプションは、空でも必ずカンマ区切りの1つの引数として渡します。
        # ここで指定しておくと、呼び出し元が後ろへ同じオプションを足しても2回目の指定として弾かれます。
        "--mount-options"
        (lib.concatStringsSep "," device.mountOptions)
        "--btrfs-mount-options"
        (lib.concatStringsSep "," device.btrfsMountOptions)
      ];
      unmountArguments = [
        "unmount"
        "--name"
        name
      ];
      # `--add-flags`の値はラッパのスクリプトへそのまま埋まるので、
      # 引数ごとにクォートしてから、ビルドのシェルに渡すためにもう一度クォートします。
      flags = arguments: lib.escapeShellArg (lib.escapeShellArgs arguments);
    in
    pkgs.runCommand "removable-crypt-${name}" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
      makeWrapper ${lib.getExe removable-crypt} $out/bin/${lib.escapeShellArg "mnt-${name}"} \
        --add-flags ${flags mountArguments}
      makeWrapper ${lib.getExe removable-crypt} $out/bin/${lib.escapeShellArg "umnt-${name}"} \
        --add-flags ${flags unmountArguments}
    '';

  allCommands = lib.mapAttrsToList mkCommands cfg.devices;

in
{
  options.programs.removable-crypt = {
    enable = lib.mkEnableOption "encrypted removable device management";

    devices = lib.mkOption {
      type = lib.types.attrsOf deviceType;
      default = { };
      description = "manage these removable encrypted devices";
      example = lib.literalExpression ''
        {
          two-thousand.deviceId = "usb-JetFlash_Transcend_32GB_25XSK57XTBIHQODC-0:0-part1";
        };
      '';
    };

    snapper = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "automatically generate snapper configs for btrfs devices";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.devices != { }) {
    assertions =
      let
        invalidNames = lib.filter (name: builtins.match dmNamePattern name == null) (
          lib.attrNames cfg.devices
        );
      in
      [
        {
          assertion = invalidNames == [ ];
          message = ''
            programs.removable-crypt.devices:
            invalid device name(s): ${lib.concatStringsSep ", " invalidNames}.
            Names must match ${dmNamePattern}.
          '';
        }
      ];
    environment.systemPackages = allCommands;

    services.snapper.configs = lib.mkIf cfg.snapper (
      lib.mapAttrs (name: _device: {
        SUBVOLUME = "/mnt/${name}";
        # スナップショットの作成と掃除は`removable-crypt`がマウント時とアンマウント時に行う。
        # systemdのtimerに任せると、挿していない間はマウントポイントが無くて失敗する。
        TIMELINE_CREATE = false;
        TIMELINE_CLEANUP = false;

        # マウント時に実行する`snapper cleanup timeline`が読む。
        # 空き容量が逼迫した時に世代数の下限まで追加で削除する。
        # 範囲指定が必要な理由やSPACE_LIMITを使わない理由は、
        # rootの設定がある`nixos/native-linux/snapper.nix`に書いている。
        TIMELINE_LIMIT_HOURLY = "2-10";
        TIMELINE_LIMIT_DAILY = "2-10";
        TIMELINE_LIMIT_MONTHLY = "2-10";
        TIMELINE_LIMIT_YEARLY = "2-10";
        FREE_LIMIT = "0.2";
      }) cfg.devices
    );
  };
}
