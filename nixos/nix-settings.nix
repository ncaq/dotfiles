{ ... }:
{
  nix.settings = {
    experimental-features = [
      "flakes"
      "nix-command"
    ];
    substituters = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org"
      "https://iohk.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "iohk.cachix.org-1:DpRUyj7h7V830dp/i6Nti+NEO2/nhblbov/8MW7Rqoo="
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
