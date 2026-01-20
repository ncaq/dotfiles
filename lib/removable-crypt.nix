{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.removable-crypt;

  deviceType = lib.types.submodule {
    options = {
      deviceId = lib.mkOption {
        type = lib.types.str;
        description = "id of under `/dev/disk/by-id/`";
        example = "usb-SanDisk_Extreme_Pro_4C530001234567891234-0:0-part1";
      };
    };
  };

  mkMountCommand =
    name: device:
    pkgs.writeShellApplication {
      name = "mnt-${name}";
      runtimeInputs = [ pkgs.udisks ];
      text = ''
        device-path="/dev/disk/by-id/${device.deviceId}"
        if [[ ! -e "$device" ]]; then
          echo "error: device not found: $device-path" >&2
          exit 1
        fi
        udisksctl unlock -b "$device-path"
        udisksctl mount -b "$device-path"
      '';
    };

  mkUnmountCommand =
    name: device:
    pkgs.writeShellApplication {
      name = "umnt-${name}";
      runtimeInputs = [ pkgs.udisks ];
      text = ''
        device-path="/dev/disk/by-id/${device.deviceId}"
        if [[ ! -e "$device" ]]; then
          echo "error: device not found: $device-path" >&2
          exit 1
        fi
        udisksctl unmount -b "$device-path"
        udisksctl lock -b "$device-path"
      '';
    };

  allCommands =
    (lib.mapAttrsToList mkMountCommand cfg.devices)
    ++ (lib.mapAttrsToList mkUnmountCommand cfg.devices);

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
  };

  config = lib.mkIf (cfg.enable && cfg.devices != { }) {
    home.packages = allCommands;
  };
}
