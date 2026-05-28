{
  nixpkgs,
  lib,
  importPkgsUnstable,
  importDirModules,
  inputs,
}:
{
  system,
  hostName,
}:
let
  specialArgs = {
    inherit
      importDirModules
      inputs

      hostName
      ;
    username = "ncaq";
  };
  modules = [
    {
      inherit nixpkgs;
    }
    inputs.disko.nixosModules.default
    inputs.sops-nix.nixosModules.sops
    ../nixos/configuration.nix
    ../nixos/host/${hostName}.nix
    inputs.home-manager.nixosModules.home-manager
    (
      { config, ... }:
      {
        home-manager = {
          backupFileExtension = "hm-bak";
          useGlobalPkgs = true;
          useUserPackages = true;
          extraSpecialArgs = specialArgs // {
            pkgs-unstable = importPkgsUnstable system;
            isTermux = false;
            isWSL = config.wsl.enable or false;
          };
          sharedModules = [
            inputs.sops-nix.homeManagerModules.sops
          ];
          users.ncaq = import ../home;
        };
      }
    )
  ];
in
{
  nixosSystem = lib.nixosSystem {
    inherit modules specialArgs system;
  };
  inherit modules specialArgs system;
}
