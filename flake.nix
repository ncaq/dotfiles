{
  description = "dotfiles, NixOS and home-manager.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      flake-parts,
      treefmt-nix,
      home-manager,
      nixos-wsl,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.home-manager.flakeModules.home-manager
        inputs.treefmt-nix.flakeModule
      ];

      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      flake = {
        homeConfigurations =
          let
            mkLinuxHome =
              username:
              home-manager.lib.homeManagerConfiguration ({
                pkgs = nixpkgs.legacyPackages.x86_64-linux;
                modules = [ ./home.nix ];
                extraSpecialArgs = { inherit username; };
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
                inherit inputs;
                username = "ncaq";
              };
            in
            nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              specialArgs = specialArgs;
              modules = [
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

          devShells.default = pkgs.mkShell { };
        };
    };
}
