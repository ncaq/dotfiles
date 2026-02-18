{ lib, ... }:
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
        description = "User ID (must match between host and container for PostgreSQL peer auth)";
      };
      gid = lib.mkOption {
        type = lib.types.int;
        description = "Group ID (must match between host and container for PostgreSQL peer auth)";
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
    };
    description = "Container user/group IDs for PostgreSQL peer authentication";
  };

  /**
    microVMのvsock CID割り当て一覧です。
    vsock CIDは仮想マシンを識別するための32bit整数値で、
    以下の値が予約されています:

    - 0: ハイパーバイザー
    - 1: ループバック
    - 2: ホスト

    したがって3以上の任意の整数を設定します。
    cloud-hypervisorはvsock経由でsystemd-notifyが使えるため、
    ホストのsystemdがVM内のサービス起動完了を正確に検知できます。
  */
  options.microvmCid = lib.mkOption {
    type = lib.types.attrsOf lib.types.int;
    default = {
      mcp-nixos = 3;
    };
    description = "vsock CID assignments for microVMs (must be >= 3, unique per VM)";
  };

  config = {
    networking.nat = {
      enable = true;
      internalInterfaces = [
        "ve-+" # container veth interfaces
        "vm-+" # microVM TAP interfaces
      ];
    };
    # Trust container/microVM interfaces for local host-to-guest communication.
    networking.firewall.trustedInterfaces = [
      "ve-+" # container veth interfaces
    ];
  };
}
