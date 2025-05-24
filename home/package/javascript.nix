{ pkgs, ... }:
{
  home.packages = with pkgs; [
    corepack
    nodePackages.prettier
    nodejs
    typescript
    typescript-language-server
    vscode-langservers-extracted
  ];
}
