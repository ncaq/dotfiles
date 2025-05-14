# all re-export.
{ lib, ... }:
let
  nixFiles = builtins.readDir ./.;
  moduleFiles = lib.filterAttrs (
    name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
  ) nixFiles;
  modules = lib.mapAttrsToList (name: _: ./${name}) moduleFiles;
in
modules
