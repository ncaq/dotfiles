{
  description = "dotfiles, NixOS and home-manager.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

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

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dot-xmonad.url = "github:ncaq/.xmonad";
  };

  outputs =
    inputs@{
      nixpkgs,
      flake-parts,
      treefmt-nix,
      home-manager,
      nixos-wsl,
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
                pkgs = nixpkgs.legacyPackages.x86_64-linux;
                modules = [
                  ./unfree.nix
                  ./home.nix
                ];
                extraSpecialArgs = {
                  inherit inputs dot-xmonad username;
                  isWSL = false;
                };
              });
          in
          {
            "ncaq" = mkLinuxHome "ncaq";
            "GitHub-Actions" = mkLinuxHome "runner";
          };

        nixosConfigurations = {
          "SSD0086" =
            let
              specialArgs = {
                inherit inputs dot-xmonad;
                username = "ncaq";
                isWSL = true;
              };
            in
            nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                ./unfree.nix
                nixos-wsl.nixosModules.default
                ./nixos/configuration.nix
                ./nixos/host/SSD0086.nix
                home-manager.nixosModules.home-manager
                {
                  home-manager = {
                    useGlobalPkgs = true;
                    useUserPackages = true;
                    extraSpecialArgs = specialArgs;
                    users.ncaq = import ./home.nix;
                  };
                }
              ];
              inherit specialArgs;
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
                  nix build --print-out-paths '.#homeConfigurations.GitHub-Actions.activationPackage'|cachix push ncaq-dotfiles
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
      "https://cache.iog.io"
      "https://nix-community.cachix.org"
      "https://ncaq-dotfiles.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "ncaq-dotfiles.cachix.org-1:oEM1SL5sNteDM16I23/rFZwKl+Anca/PnEWp6LWUrws="
    ];
  };
}
