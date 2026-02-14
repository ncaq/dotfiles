{
  description = "dotfiles, NixOS and home-manager.";

  inputs = {
    nixpkgs.follows = "nixpkgs-2511";
    nixpkgs-2511.url = "github:NixOS/nixpkgs/nixos-25.11";
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

    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-24.05";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    emacs-overlay = {
      url = "github:nix-community/emacs-overlay";
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

    dot-emacs = {
      url = "github:ncaq/.emacs.d";
      flake = false;
    };

    dot-xmonad = {
      url = "github:ncaq/.xmonad";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
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
      nix-on-droid,
      nixos-hardware,
      disko,
      sops-nix,
      emacs-overlay,
      www-ncaq-net,
      dot-emacs,
      dot-xmonad,
      claude-desktop,
      firge-nix,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } (top: {
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
            "claude-code-bin" # Node版とBun版両方受け入れると指定する必要があります。
            "copilot-language-server" # 一番いい補完のため仕方がない。
            "discord" # ネイティブ版の方が音声などが安定しているため仕方がない。
            "slack" # ネイティブ版の方が通知などが安定しているため仕方がない。
            "zoom" # ネイティブ版の方が動画などが安定しているため仕方がない。
          ];
          nixpkgsConfig = {
            inherit allowlistedLicenses;
            allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) allowedUnfreePackages;
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
                      dot-emacs
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
                      nixpkgs = {
                        config = nixpkgsConfig;
                        overlays = [
                          emacs-overlay.overlays.default
                          firge-nix.overlays.default
                        ];
                      };
                    })
                    disko.nixosModules.default
                    sops-nix.nixosModules.sops
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
                            pkgs-unstable = import nixpkgs-unstable {
                              inherit system;
                              config = nixpkgsConfig;
                              overlays = [
                                emacs-overlay.overlays.default
                                firge-nix.overlays.default
                              ];
                            };
                            isTermux = false;
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
                    overlays = [
                      emacs-overlay.overlays.default
                      firge-nix.overlays.default
                    ];
                  };
                  extraSpecialArgs = {
                    inherit
                      claude-desktop
                      dot-emacs
                      dot-xmonad
                      importDirModules
                      inputs
                      www-ncaq-net

                      username
                      ;
                    pkgs-unstable = import nixpkgs-unstable {
                      inherit system;
                      config = nixpkgsConfig;
                      overlays = [
                        emacs-overlay.overlays.default
                        firge-nix.overlays.default
                      ];
                    };
                    isTermux = false;
                    isWSL = false;
                  };
                  modules = [
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

          nixOnDroidConfigurations = {
            default = import ./nix-on-droid {
              inherit
                dot-emacs
                emacs-overlay
                firge-nix
                home-manager
                importDirModules
                inputs
                nix-on-droid
                nixpkgs
                nixpkgs-unstable
                nixpkgsConfig
                sops-nix
                www-ncaq-net
                ;
              system = "aarch64-linux";
              username = "ncaq";
            };
          };
        };

      perSystem =
        {
          pkgs,
          system,
          ...
        }:
        {
          checks =
            let
              # NixOS構成の評価チェック(評価のみ、ビルドしない)
              nixosEvalChecks =
                nixpkgs.lib.mapAttrs'
                  (
                    name: nixosConfig:
                    nixpkgs.lib.nameValuePair "nixos-eval-${name}" (
                      builtins.seq nixosConfig.config.system.build.toplevel.drvPath (
                        pkgs.writeText "nixos-eval-${name}" name
                      )
                    )
                  )
                  (
                    nixpkgs.lib.filterAttrs (
                      _: nixosConfig: nixosConfig.pkgs.system == system
                    ) top.config.flake.nixosConfigurations
                  );
              # home-manager構成の評価チェック
              hmEvalChecks = nixpkgs.lib.optionalAttrs (top.config.flake.homeConfigurations ? ${system}) {
                "hm-eval" = builtins.seq top.config.flake.homeConfigurations.${system}.activationPackage.drvPath (
                  pkgs.writeText "hm-eval-${system}" system
                );
              };
            in
            nixosEvalChecks // hmEvalChecks;

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
              };
            };
          };
          packages = {
            # flake.lockの管理バージョンをre-exportすることで安定した利用を促進。
            inherit (pkgs)
              disko
              fastfetch
              git
              home-manager
              ;
          };
          devShells.default = pkgs.mkShell { };
        };
    });

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org/"
      "https://nix-on-droid.cachix.org/"
      "https://ncaq-dotfiles.cachix.org/"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nix-on-droid.cachix.org-1:56snoMJTXmDRC1Ei24CmKoUqvHJ9XCp+nidK7qkMQrU="
      "ncaq-dotfiles.cachix.org-1:oEM1SL5sNteDM16I23/rFZwKl+Anca/PnEWp6LWUrws="
    ];
  };
}
