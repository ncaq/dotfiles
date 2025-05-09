{ ... }:
{
  projectRootFile = "flake.nix";

  programs = {
    nixfmt.enable = true;
    shellcheck.enable = true;
    shfmt.enable = true;
  };
}
