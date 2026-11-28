{
  importPkgsStable,
  importPkgsUnstable,
  importDirModules,
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
    inherit
      importDirModules
      localLib
      inputs

      username
      ;
    pkgs-unstable = importPkgsUnstable system;
    isTermux = false;
    isWSL = false;
  };
  modules = [
    inputs.sops-nix.homeManagerModules.sops
    ./.
  ];
}
