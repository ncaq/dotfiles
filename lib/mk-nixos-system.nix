{
  lib,
  importPkgsStable,
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
    # 共有のpkgsインスタンスをNixOSに渡し、
    # ホストごとにnixpkgs全体を再評価することによるメモリ重複を防ぐ。
    # `nixpkgs.overlays`は`appendOverlays`で後から追加されるため、
    # CPU最適化overlayなどホスト固有のoverlayは引き続き有効。
    { nixpkgs.pkgs = importPkgsStable system; }
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
