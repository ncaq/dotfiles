{ pkgs, ... }:
{
  home.packages = with pkgs; [
    nodePackages.prettier
    nodejs
    typescript
    typescript-language-server
    vscode-langservers-extracted
  ];
}
