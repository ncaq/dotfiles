{ lib, config, ... }:
let
  addressType = lib.types.submodule {
    options = {
      host = lib.mkOption {
        type = lib.types.str;
        description = "Host-side IP address";
      };
      guest = lib.mkOption {
        type = lib.types.str;
        description = "Guest-side IP address (container or microVM)";
      };
    };
  };
  userType = lib.types.submodule {
    options = {
      uid = lib.mkOption {
        type = lib.types.int;
        description = "Container user ID (must match between host and container)";
      };
      gid = lib.mkOption {
        type = lib.types.int;
        description = "Container group ID (must match between host and container)";
      };
    };
  };
in
{
  options.machineAddresses = lib.mkOption {
    type = lib.types.attrsOf addressType;
    default = {
      forgejo = {
        host = "192.168.100.10";
        guest = "192.168.100.11";
      };
      atticd = {
        host = "192.168.100.20";
        guest = "192.168.100.21";
      };
      mcp-nixos = {
        host = "192.168.100.30";
        guest = "192.168.100.31";
      };
      github-runner-seminar-dotfiles-x64 = {
        host = "192.168.100.40";
        guest = "192.168.100.41";
      };
    };
    description = "Network addresses for containers and microVMs";
  };

  options.containerUsers = lib.mkOption {
    type = lib.types.attrsOf userType;
    default = {
      forgejo = {
        uid = 991;
        gid = 986;
      };
      atticd = {
        uid = 993;
        gid = 988;
      };
      github-runner = {
        uid = 980;
        gid = 980;
      };
    };
    description = "Container user/group IDs (must match between host and container)";
  };

  /**
    microVMのvsock CID割り当て一覧です。
    vsock CIDは仮想マシンを識別するための32bit整数値で、
    以下の値が予約されています:

    - 0: ハイパーバイザー
    - 1: ループバック
    - 2: ホスト
    - 0xFFFFFFFF: VMADDR_CID_ANY

    cloud-hypervisorはvsock経由でsystemd-notifyが使えるため、
    ホストのsystemdがVM内のサービス起動完了を正確に検知できます。
  */
  options.microvmCid = lib.mkOption {
    type = lib.types.attrsOf (lib.types.ints.between 3 4294967294);
    default = {
      mcp-nixos = 3;
    };
    description = "vsock CID assignments for microVMs (must be >= 3, unique per VM)";
  };

  config = {
    assertions =
      let
        cidValues = lib.attrValues config.microvmCid;
        uniqueValues = lib.unique cidValues;
      in
      [
        {
          assertion = lib.length cidValues == lib.length uniqueValues;
          message = "microvmCid values must be unique, but found duplicates: ${
            lib.concatMapStringsSep ", " toString cidValues
          }";
        }
      ];

    networking.nat = {
      enable = true;
      internalInterfaces = [
        "ve-+" # container veth interfaces
        "vm-+" # microVM TAP interfaces
      ];
    };
  };
}
