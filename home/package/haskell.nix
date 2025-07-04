{ pkgs, ... }:
let
  yamlFormat = pkgs.formats.yaml { };
  stackConfig = {
    system-ghc = true;
    install-ghc = false;
    ghc-options = {
      "$everything" = "-haddock";
    }; # for HLS.
    templates = {
      params = {
        author-email = "ncaq@ncaq.net";
        author-name = "ncaq";
        github-username = "ncaq";
        scm-init = "git";
      };
    };
    color = "auto";
    stack-colors = "error=31:good=32:shell=35:dir=34:recommendation=32:target=95:module=35:package-component=95:secondary=92:highlight=32";
  };
in
{
  home.packages =
    (with pkgs; [
      cabal-install
      cabal2nix
      fourmolu
      ghc
      haskell-ci
      haskell-language-server
      hlint
      hpack
      pandoc
      stack
      stylish-haskell
    ])
    ++ (with pkgs.haskellPackages; [
      cabal-fmt
      cabal-gild
      cabal-plan
      implicit-hie
      uniq-deep
    ]);

  home.file.".stack/config.yaml".source = yamlFormat.generate "stack-config" stackConfig;
}
