{ pkgs, ... }:
{
  # 様々なツールで利用するlspサーバをインストールします。
  # Emacsなどのテキストエディタや、
  # コーディングエージェントなどが利用します。
  home.packages = with pkgs; [
    bash-language-server
    ccls
    clang-tools
    clojure-lsp
    cmake-language-server
    csharp-ls
    dhall-lsp-server
    docker-compose-language-service
    dockerfile-language-server
    elixir-ls
    elmPackages.elm-language-server
    erlang-language-platform
    fortls
    gopls
    graphql-language-service-cli
    haskell-language-server
    jdt-language-server
    kotlin-language-server
    ltex-ls-plus
    lua-language-server
    marksman
    metals
    nginx-language-server
    nil
    ocamlPackages.ocaml-lsp
    omnisharp-roslyn
    pyright
    ruby-lsp
    rust-analyzer
    serve-d
    sourcekit-lsp
    sqls
    svelte-language-server
    tailwindcss-language-server
    taplo
    terraform-ls
    texlab
    typescript-language-server
    vscode-langservers-extracted
    vue-language-server
    yaml-language-server
    zls
  ];
}
