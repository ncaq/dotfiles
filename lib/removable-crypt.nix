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

  # デバイスごとの`mnt-<名前>`と`umnt-<名前>`。
  # 中身は`pkgs/removable-crypt`にあります。
  mkCommands =
    name: device:
    pkgs.callPackage ../pkgs/removable-crypt {
      inherit name;
      inherit (device) deviceId mountOptions btrfsMountOptions;
      systemd = config.systemd.package;
    };

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
        TIMELINE_CREATE = false;
        TIMELINE_CLEANUP = false;
      }) cfg.devices
    );
  };
}
