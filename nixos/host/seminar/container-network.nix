{ lib, ... }:
let
  addressType = lib.types.submodule {
    options = {
      host = lib.mkOption {
        type = lib.types.str;
        description = "Host-side IP address for the container";
      };
      container = lib.mkOption {
        type = lib.types.str;
        description = "Container-side IP address";
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
  options.containerAddresses = lib.mkOption {
    type = lib.types.attrsOf addressType;
    default = {
      forgejo = {
        host = "192.168.100.10";
        container = "192.168.100.11";
      };
      atticd = {
        host = "192.168.100.20";
        container = "192.168.100.21";
      };
    };
    description = "Container network addresses";
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
      internalInterfaces = [ "ve-+" ];
    };
  };
}
