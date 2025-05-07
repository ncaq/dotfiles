{ pkgs, ... }:
{
  home.packages = with pkgs; [
    nodePackages.prettier
    nodejs
    pnpm
    typescript
    yarn
  ];
}
