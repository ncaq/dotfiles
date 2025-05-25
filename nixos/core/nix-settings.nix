{ ... }:
{
  nix.settings = {
    experimental-features = [
      "flakes"
      "nix-command"
    ];
    substituters = [
      "https://cache.nixos.org"
      "https://cache.iog.io"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
    cores = 0;
    max-jobs = "auto";
    accept-flake-config = true;
    trusted-users = [
      "root"
      "@wheel"
    ];
  };
}
