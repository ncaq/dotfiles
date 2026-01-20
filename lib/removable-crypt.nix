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
        description = "ID of the device under `/dev/disk/by-id/`";
        example = "usb-JetFlash_Transcend_32GB_25XSK57XTBIHQODC-0:0-part1";
      };
    };
  };

  mkMountCommand =
    name: device:
    pkgs.writeShellApplication {
      name = "mnt-${name}";
      runtimeInputs = [
        pkgs.cryptsetup
        pkgs.util-linux
      ];
      text = ''
        device_path="/dev/disk/by-id/${device.deviceId}"
        mapper_name="${name}"
        mount_point="/run/media/$USER/${name}"

        if [[ ! -e "$device_path" ]]; then
          echo "error: device not found: $device_path" >&2
          exit 1
        fi

        sudo cryptsetup open "$device_path" "$mapper_name"
        mkdir -p "$mount_point"
        sudo mount "/dev/mapper/$mapper_name" "$mount_point"
      '';
    };

  mkUnmountCommand =
    name: _device:
    pkgs.writeShellApplication {
      name = "umnt-${name}";
      runtimeInputs = [
        pkgs.cryptsetup
        pkgs.util-linux
      ];
      text = ''
        mapper_name="${name}"
        mount_point="/run/media/$USER/${name}"

        sudo umount "$mount_point"
        rmdir "$mount_point"
        sudo cryptsetup close "$mapper_name"
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
    environment.systemPackages = allCommands;
  };
}
