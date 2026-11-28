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
    # NixOSの外で使うのは人が直接操作するクライアントPCなので、GUIの設定も読み込む。
    isClient = true;
  };
  modules = [
    inputs.sops-nix.homeManagerModules.sops
    ./.
  ];
}
