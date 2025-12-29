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

  config = {
    networking.nat = {
      enable = true;
      internalInterfaces = [ "ve-+" ];
    };
  };
}
