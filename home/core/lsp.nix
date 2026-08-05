{ pkgs, ... }:
{
  home.packages = with pkgs; [
    ccls
    clang-tools
    csharp-ls
    docker-compose-language-service
    dockerfile-language-server
    gopls
    haskell-language-server
    jdt-language-server
    kotlin-language-server
    lua-language-server
    marksman
    nil
    ruby-lsp
    sourcekit-lsp
    typescript-language-server
    vscode-langservers-extracted
  ];
}
