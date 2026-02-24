{ pkgs, ... }:
{
  home.packages = with pkgs; [
    corepack
    nodejs
    npm-check-updates
    prettier
    typescript
    typescript-language-server
    vscode-langservers-extracted
  ];
}
