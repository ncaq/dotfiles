{ pkgs, ... }:
{
  # 様々なツールで利用するlspサーバをインストールします。
  # Emacsなどのテキストエディタや、
  # コーディングエージェントなどが利用します。
  home.packages = with pkgs; [
    astro-language-server # Astro
    bash-language-server # Bashなどのシェルスクリプト
    biome # JavaScriptやTypeScriptなどのWeb言語
    ccls # CとC++
    clang-tools # CとC++向けのclangdを含みます
    clojure-lsp # Clojure
    cmake-language-server # CMake
    csharp-ls # C#
    dart # Dart SDK内蔵のLanguage Server
    dhall-lsp-server # Dhall
    docker-compose-language-service # Docker Compose
    dockerfile-language-server # Dockerfile
    elixir-ls # Elixir
    elmPackages.elm-language-server # Elm
    erlang-language-platform # Erlang
    fortls # Fortran
    fsautocomplete # F#
    gleam # Gleam内蔵のLanguage Server
    gopls # Go
    graphql-language-service-cli # GraphQL
    haskell-language-server # Haskell
    jdt-language-server # Java
    kotlin-language-server # Kotlin
    ltex-ls-plus # LaTeXやMarkdownなどの文法・スペル検査
    lua-language-server # Lua
    marksman # Markdown
    metals # Scala
    nginx-language-server # nginx設定
    nil # Nix
    nixd # Nix、評価や補完機能が豊富な実装
    ocamlPackages.ocaml-lsp # OCaml
    omnisharp-roslyn # C#向けのOmniSharp
    oxlint # JavaScriptやTypeScript向けの高速LSPとlinter
    prisma_7 # Prisma CLI内蔵のLanguage Server
    pyright # Pythonの型検査と補完
    ruby-lsp # Ruby
    serve-d # D
    sourcekit-lsp # SwiftとObjective-C
    sqls # SQL
    svelte-language-server # Svelte
    tailwindcss-language-server # Tailwind CSS
    taplo # TOML
    terraform-ls # Terraform
    texlab # LaTeX
    tinymist # Typst
    ty # Python向けの高速な型検査と補完
    typescript-language-server # TypeScriptとJavaScript
    vscode-langservers-extracted # HTML、CSS、JSON、ESLint
    vue-language-server # Vue
    yaml-language-server # YAML
    zls # Zig
  ];
}
