{
  lib,
  importPkgsStable,
  importPkgsUnstable,
  localLib,
  inputs,
}:
{
  system,
  hostName,
  hostInfo,
}:
let
  # WSL2の上で動くホストかどうか。
  # 構成の`wsl.enable`ではなく静的な`hostInfo`から取るので、構成を評価せずに分かる。
  isWSL = hostInfo.${hostName}.wsl or false;
  # `client`層を読み込むクライアントPCかどうか。
  isClient = hostInfo.${hostName}.client or false;
  specialArgs = {
    # 使う箇所が多いものは、`localLib`から取り出して単独の引数としても配る。
    inherit (localLib) importDirModules hardening;
    inherit
      localLib
      inputs

      hostName
      hostInfo
      ;
    username = "ncaq";
    pkgs-unstable = importPkgsUnstable system;
  };
  modules = [
    # 共有のpkgsインスタンスをNixOSに渡し、
    # ホストごとにnixpkgs全体を再評価することによるメモリ重複を防ぐ。
    # `nixpkgs.overlays`は`appendOverlays`で後から追加されるため、
    # CPU最適化overlayなどホスト固有のoverlayは引き続き有効。
    { nixpkgs.pkgs = importPkgsStable system; }
    inputs.disko.nixosModules.default
    inputs.sops-nix.nixosModules.sops
    ./configuration.nix
    ./host/${hostName}.nix
    inputs.home-manager.nixosModules.home-manager
    {
      home-manager = {
        backupFileExtension = "hm-bak";
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = specialArgs // {
          inherit isWSL isClient;
          isTermux = false;
        };
        sharedModules = [
          inputs.sops-nix.homeManagerModules.sops
        ];
        users.ncaq = import ../home;
      };
    }
  ];
in
{
  nixosSystem = lib.nixosSystem {
    inherit modules specialArgs system;
  };
  inherit
    modules
    specialArgs
    system
    isWSL
    ;
}
