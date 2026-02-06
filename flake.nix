{
  description = "dotfiles, NixOS and home-manager.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-utils.url = "github:numtide/flake-utils";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-hooks = {
      url = "github:ncaq/git-hooks";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
      };
    };

    www-ncaq-net = {
      url = "github:ncaq/www.ncaq.net";
      flake = false;
    };

    dot-xmonad = {
      url = "github:ncaq/.xmonad";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        haskellNix.inputs = {
          nixpkgs-unstable.follows = "nixpkgs-unstable";
        };
        flake-utils.follows = "flake-utils";
        treefmt-nix.follows = "treefmt-nix";
      };
    };

    claude-desktop = {
      url = "github:k3d3/claude-desktop-linux-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    firge-nix = {
      url = "github:ncaq/firge-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      nixpkgs-unstable,
      flake-parts,
      treefmt-nix,
      home-manager,
      nixos-wsl,
      nixos-hardware,
      sops-nix,
      disko,
      rust-overlay,
      www-ncaq-net,
      dot-xmonad,
      claude-desktop,
      firge-nix,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        home-manager.flakeModules.home-manager
        treefmt-nix.flakeModule
      ];

      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      flake =
        let
          # ディレクトリ内の全.nixファイルをimportするヘルパー関数。
          importDirModules = import ./lib/import-dir-modules.nix { inherit (nixpkgs) lib; };
          # 許可するライセンス。
          allowlistedLicenses = with nixpkgs.lib.licenses; [
            nvidiaCudaRedist # 再配布可能ならまだマシ。
            unfreeRedistributable # 再配布可能ならまだマシ。
          ];
          # 明示的に許可するunfreeパッケージのリスト。
          allowedUnfreePackages = [
            "claude-code" # 一番使いやすいLLMエージェントのため仕方がない。
            "discord" # ネイティブ版の方が音声などが安定しているため仕方がない。
            "slack" # ネイティブ版の方が通知などが安定しているため仕方がない。
            "zoom" # ネイティブ版の方が動画などが安定しているため仕方がない。
          ];
          nixpkgsConfig = {
            inherit allowlistedLicenses;
            allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) allowedUnfreePackages;
          };
          mkPkgsUnstable =
            system:
            import nixpkgs-unstable {
              inherit system;
              config = nixpkgsConfig;
            };
        in
        {
          nixosConfigurations =
            let
              mkNixosSystem =
                {
                  hostName,
                  system,
                }:
                let
                  specialArgs = {
                    inherit
                      claude-desktop
                      dot-xmonad
                      importDirModules
                      inputs
                      www-ncaq-net

                      hostName
                      nixos-hardware
                      nixos-wsl
                      ;
                    username = "ncaq";
                  };
                in
                nixpkgs.lib.nixosSystem {
                  inherit
                    specialArgs
                    system
                    ;
                  modules = [
                    (_: {
                      nixpkgs.config = nixpkgsConfig;
                      nixpkgs.overlays = [
                        rust-overlay.overlays.default
                        firge-nix.overlays.default
                      ];
                    })
                    sops-nix.nixosModules.sops
                    disko.nixosModules.default
                    ./nixos/configuration.nix
                    ./nixos/host/${hostName}.nix
                    home-manager.nixosModules.home-manager
                    (
                      { config, ... }:
                      {
                        home-manager = {
                          backupFileExtension = "hm-bak";
                          useGlobalPkgs = true;
                          useUserPackages = true;
                          extraSpecialArgs = specialArgs // {
                            pkgs-unstable = mkPkgsUnstable system;
                            isWSL = config.wsl.enable or false;
                          };
                          sharedModules = [
                            sops-nix.homeManagerModules.sops
                          ];
                          users.ncaq = import ./home;
                        };
                      }
                    )
                  ];
                };
            in
            {
              "SSD0086" = mkNixosSystem {
                system = "x86_64-linux";
                hostName = "SSD0086";
              };
              "bullet" = mkNixosSystem {
                system = "x86_64-linux";
                hostName = "bullet";
              };
              "creep" = mkNixosSystem {
                system = "x86_64-linux";
                hostName = "creep";
              };
              "seminar" = mkNixosSystem {
                system = "x86_64-linux";
                hostName = "seminar";
              };
              "vanitas" = mkNixosSystem {
                system = "x86_64-linux";
                hostName = "vanitas";
              };
            };

          homeConfigurations =
            let
              mkLinuxHome =
                {
                  system,
                  username,
                }:
                home-manager.lib.homeManagerConfiguration {
                  pkgs = import nixpkgs {
                    inherit system;
                    config = nixpkgsConfig;
                  };
                  extraSpecialArgs = {
                    inherit
                      claude-desktop
                      dot-xmonad
                      importDirModules
                      inputs
                      www-ncaq-net

                      username
                      ;
                    pkgs-unstable = mkPkgsUnstable system;
                    isWSL = false;
                  };
                  modules = [
                    (_: {
                      nixpkgs.config = nixpkgsConfig;
                      nixpkgs.overlays = [
                        rust-overlay.overlays.default
                        firge-nix.overlays.default
                      ];
                    })
                    sops-nix.homeManagerModules.sops
                    ./home
                  ];
                };
            in
            {
              "x86_64-linux" = mkLinuxHome {
                system = "x86_64-linux";
                username = "ncaq";
              };
              "aarch64-linux" = mkLinuxHome {
                system = "aarch64-linux";
                username = "ncaq";
              };
            };
        };

      perSystem =
        {
          pkgs,
          inputs',
          ...
        }:
        {
          treefmt.config = {
            projectRootFile = "flake.nix";
            programs = {
              actionlint.enable = true;
              deadnix.enable = true;
              nixfmt.enable = true;
              prettier.enable = true;
              shellcheck.enable = true;
              shfmt.enable = true;
              zizmor.enable = true;

              statix = {
                enable = true;
                disabled-lints = [ "eta_reduction" ];
              };
              typos = {
                enable = true;
                excludes = [
                  "key/*"
                  "mozc/*"
                  "secrets/*"
                ];
              };
            };
            settings.formatter = {
              editorconfig-checker = {
                command = pkgs.lib.getExe (
                  pkgs.writeShellApplication {
                    name = "editorconfig-checker-wrapper";
                    runtimeInputs = [ pkgs.editorconfig-checker ];
                    text = ''
                      editorconfig-checker -config .editorconfig-checker.json "$@"
                    '';
                  }
                );
                includes = [ "*" ];
                excludes = [
                  ".git/*"
                  ".direnv/*"
                  "result*"
                ];
              };
            };
          };
          apps = {
            home-manager = {
              type = "app";
              meta.description = "Manage user configuration with Nix";
              program = "${inputs'.home-manager.packages.home-manager}/bin/home-manager";
            };
            disko = {
              type = "app";
              meta.description = "Declarative disk partitioning";
              program = "${inputs'.disko.packages.disko}/bin/disko";
            };
            fastfetch = {
              type = "app";
              meta.description = "Fast system information tool";
              program = "${pkgs.fastfetch}/bin/fastfetch";
            };
          };
          devShells.default = pkgs.mkShell { };
        };
    };

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org/"
      "https://cache.iog.io/"
      "https://ncaq-dotfiles.cachix.org/"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
      "ncaq-dotfiles.cachix.org-1:oEM1SL5sNteDM16I23/rFZwKl+Anca/PnEWp6LWUrws="
    ];
  };
}
