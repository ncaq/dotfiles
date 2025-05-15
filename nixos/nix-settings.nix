{ ... }:
{
  nix.settings = {
    experimental-features = [
      "flakes"
      "nix-command"
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
