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

  mkMountCommand =
    name: device:
    pkgs.writeShellApplication {
      name = "mnt-${name}";
      runtimeInputs = [
        pkgs.cryptsetup
        pkgs.util-linux
      ];
      text = ''
        if [[ ! -w /dev/mapper/control ]]; then
          echo "error: no permission to access /dev/mapper/control (use sudo)" >&2
          exit 1
        fi

        device_path="/dev/disk/by-id/${device.deviceId}"
        mapper_name="${name}"
        target_user="''${SUDO_USER:-$USER}"
        mount_point="/run/media/$target_user/${name}"

        if [[ ! -e "$device_path" ]]; then
          echo "error: device not found: $device_path" >&2
          exit 1
        fi

        cryptsetup open "$device_path" "$mapper_name"
        mkdir -p "$mount_point"
        chown "$target_user:$target_user" "$mount_point"

        fs_type=$(blkid -s TYPE -o value "/dev/mapper/$mapper_name")
        if [[ "$fs_type" == "btrfs" ]]; then
          mount -o "${
            lib.concatStringsSep "," (device.mountOptions ++ device.btrfsMountOptions)
          }" "/dev/mapper/$mapper_name" "$mount_point"
        else
          mount -o "${lib.concatStringsSep "," device.mountOptions}" "/dev/mapper/$mapper_name" "$mount_point"
        fi

        chown "$target_user:$target_user" "$mount_point"
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
        if [[ ! -w /dev/mapper/control ]]; then
          echo "error: no permission to access /dev/mapper/control (use sudo)" >&2
          exit 1
        fi

        mapper_name="${name}"
        target_user="''${SUDO_USER:-$USER}"
        mount_point="/run/media/$target_user/${name}"

        umount "$mount_point"
        rmdir "$mount_point"
        cryptsetup close "$mapper_name"
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
