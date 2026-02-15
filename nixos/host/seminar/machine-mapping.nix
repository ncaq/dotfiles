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
