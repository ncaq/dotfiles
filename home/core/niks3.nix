{ pkgs, inputs, ... }:
{
  home.packages = [
    inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}.niks3
  ];
}
