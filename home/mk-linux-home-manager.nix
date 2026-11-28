{
  importPkgsStable,
  importPkgsUnstable,
  localLib,
  inputs,
}:
{
  system,
  username,
}:
inputs.home-manager.lib.homeManagerConfiguration {
  pkgs = importPkgsStable system;
  extraSpecialArgs = {
    inherit (localLib) importDirModules;
    inherit
      localLib
      inputs

      username
      ;
    pkgs-unstable = importPkgsUnstable system;
    isTermux = false;
    isWSL = false;
    isServer = false;
  };
  modules = [
    inputs.sops-nix.homeManagerModules.sops
    ./.
  ];
}
