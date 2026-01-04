# Import all .nix files in a directory except default.nix.
{ lib }:
dir:
let
  nixFiles = builtins.readDir dir;
  moduleFiles = lib.filterAttrs (
    name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
  ) nixFiles;
in
lib.mapAttrsToList (name: _: lib.path.append dir name) moduleFiles
