{
  description = "dotfiles, NixOS and home-manager.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dot-xmonad = {
      url = "github:ncaq/.xmonad";
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
      nixos-hardware,
      disko,
      nixos-wsl,
      rust-overlay,
      dot-xmonad,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        home-manager.flakeModules.home-manager
        treefmt-nix.flakeModule
      ];

      systems = [
        "x86_64-linux"
      ];

      flake = {
        homeConfigurations =
          let
            mkLinuxHome =
              username:
              home-manager.lib.homeManagerConfiguration ({
                pkgs = import nixpkgs {
                  system = "x86_64-linux";
                };
                extraSpecialArgs = {
                  inherit inputs dot-xmonad username;
                  pkgs-unstable = import nixpkgs-unstable {
                    system = "x86_64-linux";
                    config.allowUnfree = true;
                  };
                  isWSL = false;
                  dpi = 144;
                };
                modules = [
                  (
                    { ... }:
                    {
                      nixpkgs.config.allowUnfree = true;
                      nixpkgs.overlays = [ rust-overlay.overlays.default ];
                    }
                  )
                  ./home
                ];
              });
          in
          {
            "ncaq" = mkLinuxHome "ncaq";
          };

        nixosConfigurations =
          let
            mkNixosSystem =
              {
                hostName,
                isWSL,
                dpi ? null,
              }:
              let
                specialArgs = {
                  inherit
                    inputs
                    hostName
                    isWSL
                    dpi
                    nixos-hardware
                    dot-xmonad
                    ;
                  pkgs-unstable = import nixpkgs-unstable {
                    system = "x86_64-linux";
                    config.allowUnfree = true;
                  };
                  username = "ncaq";
                };
              in
              nixpkgs.lib.nixosSystem {
                system = "x86_64-linux";
                inherit specialArgs;
                modules =
                  (
                    if isWSL then
                      [
                        nixos-wsl.nixosModules.default
                        ./nixos/wsl.nix
                      ]
                    else
                      [ disko.nixosModules.default ]
                  )
                  ++ [
                    (
                      { ... }:
                      {
                        nixpkgs.config.allowUnfree = true;
                        nixpkgs.overlays = [ rust-overlay.overlays.default ];
                      }
                    )
                    ./nixos/configuration.nix
                    ./nixos/host/${hostName}.nix
                    home-manager.nixosModules.home-manager
                    {
                      home-manager = {
                        useGlobalPkgs = true;
                        useUserPackages = true;
                        extraSpecialArgs = specialArgs;
                        users.ncaq = import ./home;
                      };
                    }
                  ];
              };
          in
          {
            "vanitas" = mkNixosSystem {
              hostName = "vanitas";
              isWSL = false;
              dpi = 144;
            };
            "creep" = mkNixosSystem {
              hostName = "creep";
              isWSL = false;
            };
            "SSD0086" = mkNixosSystem {
              hostName = "SSD0086";
              isWSL = true;
              dpi = 144;
            };
          };
      };

      perSystem =
        {
          pkgs,
          config,
          ...
        }:
        {
          treefmt.config = {
            projectRootFile = "flake.nix";
            programs = {
              deadnix.enable = true;
              nixfmt.enable = true;
              shellcheck.enable = true;
              shfmt.enable = true;
            };
          };
          apps = {
            cachix-push = {
              type = "app";
              meta = {
                description = "Push cache to cachix";
              };
              program = pkgs.writeShellApplication {
                name = "cachix-push";
                runtimeInputs = with pkgs; [
                  cachix
                  jq
                ];
                text = ''
                  echo "Push inputs"
                  nix flake archive --json|jq -r '.path,(.inputs|to_entries[].value.path)'|cachix push ncaq-dotfiles
                  echo "Push home-manager"
                  nix build --print-out-paths '.#homeConfigurations.ncaq.activationPackage'|cachix push ncaq-dotfiles
                  echo "Push NixOS partical"
                  nix build --print-out-paths '.#nixosConfigurations.SSD0086.config.system.build.toplevel'|cachix push ncaq-dotfiles
                '';
              };
            };
          };
          devShells.default = pkgs.mkShell { };
        };
    };

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org"
      "https://cache.iog.io"
      "https://ncaq-dotfiles.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
      "ncaq-dotfiles.cachix.org-1:oEM1SL5sNteDM16I23/rFZwKl+Anca/PnEWp6LWUrws="
    ];
  };
}
