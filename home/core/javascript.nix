{ pkgs, ... }:
{
  home.packages = with pkgs; [
    corepack
    nodejs
    prettier
    typescript
    typescript-language-server
    vscode-langservers-extracted
  ];
}
