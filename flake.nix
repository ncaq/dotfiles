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

    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    niks3 = {
      url = "github:Mic92/niks3";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
      };
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
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
      };
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
            "discord" # ネイティブ版の方が音声などが安定しているため仕方がない。
            "slack" # ネイティブ版の方が通知などが安定しているため仕方がない。
            "zoom" # ネイティブ版の方が動画などが安定しているため仕方がない。
          ];
          nixpkgsConfig = {
            inherit allowlistedLicenses;
            allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) allowedUnfreePackages;
          };
          # 全環境で共通のoverlays。
          overlays = [
            inputs.firge-nix.overlays.default
          ];
          # system固有のpkgsを生成する関数。
          importPkgsStable = importPkgsFor nixpkgs;
          importPkgsUnstable = importPkgsFor nixpkgs-unstable;
          importPkgsFor =
            pkgset: system:
            import pkgset {
              inherit system overlays;
              config = nixpkgsConfig;
            };
        in
        {
          hostDefs =
            let
              mkNixosSystem =
                {
                  hostName,
                  system,
                }:
                let
                  specialArgs = {
                    inherit
                      importDirModules
                      inputs

                      hostName
                      ;
                    username = "ncaq";
                  };
                  modules = [
                    (_: {
                      nixpkgs = {
                        config = nixpkgsConfig;
                        inherit overlays;
                      };
                    })
                    inputs.disko.nixosModules.default
                    inputs.sops-nix.nixosModules.sops
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
                            pkgs-unstable = importPkgsUnstable system;
                            isTermux = false;
                            isWSL = config.wsl.enable or false;
                          };
                          sharedModules = [
                            inputs.sops-nix.homeManagerModules.sops
                          ];
                          users.ncaq = import ./home;
                        };
                      }
                    )
                  ];
                in
                {
                  nixosSystem = nixpkgs.lib.nixosSystem {
                    inherit modules specialArgs system;
                  };
                  inherit modules specialArgs system;
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
            };

          nixosConfigurations = nixpkgs.lib.mapAttrs (_: def: def.nixosSystem) top.config.flake.hostDefs;

          nixosBootTests =
            let
              bootTestableHosts = nixpkgs.lib.filterAttrs (
                _: def: !(def.nixosSystem.config.wsl.enable or false)
              ) top.config.flake.hostDefs;
            in
            nixpkgs.lib.mapAttrs (
              name: hostDef:
              (importPkgsStable hostDef.system).testers.runNixOSTest {
                name = "boot-test-${name}";
                node = {
                  # runNixOSTestが追加するnixpkgsの読み込み専用設定を無効化します。
                  # hardware-configuration.nixが存在する時nixpkgs.hostPlatformを設定しているので、
                  # 読み込み専用にされたnixpkgsオプションへの設定がエラーになります。
                  # 基本的にモジュール単位のテスト機構であり全体のブートを想定していないゆえの挙動でしょう。
                  # 自動生成ファイルであるhardware-configuration.nixを編集したくないため、
                  # 上書きを有効にしてしまいます。
                  # ブートのテストの場合ではあまり問題にならないはずです。
                  pkgsReadOnly = false;
                  inherit (hostDef) specialArgs;
                };
                nodes.machine = {
                  imports = hostDef.modules ++ [
                    ./nixos/test/vm-override.nix
                  ];
                };
                # テスト環境はネットワークに繋がっていないため、
                # ネットワーク依存のユニットは失敗します。
                # よって全体成功を期待することはできません。
                # multi-user.targetに到達すればひとまず成功とみなしています。
                testScript = ''
                  machine.wait_for_unit("multi-user.target")
                '';
              }
            ) bootTestableHosts;

          homeConfigurations =
            let
              mkLinuxHome =
                {
                  system,
                  username,
                }:
                home-manager.lib.homeManagerConfiguration {
                  pkgs = importPkgsStable system;
                  extraSpecialArgs = {
                    inherit
                      importDirModules
                      inputs

                      username
                      ;
                    pkgs-unstable = importPkgsUnstable system;
                    isTermux = false;
                    isWSL = false;
                  };
                  modules = [
                    inputs.sops-nix.homeManagerModules.sops
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
                importDirModules
                inputs
                nixpkgsConfig
                overlays
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
                      _: nixosConfig: nixosConfig.pkgs.stdenv.hostPlatform.system == system
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
              typos.enable = true;
              zizmor.enable = true;

              statix = {
                enable = true;
                disabled-lints = [ "eta_reduction" ];
              };
            };
            settings.formatter = {
              editorconfig-checker = {
                command = pkgs.lib.getExe (
                  pkgs.writeShellApplication {
                    name = "editorconfig-checker-wrapper";
                    runtimeInputs = [ pkgs.editorconfig-checker ];
                    text = ''
                      editorconfig-checker "$@"
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
              nix-fast-build
              qemu-user
              ;
          };
          devShells.default = pkgs.mkShell { };
        };
    });

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org/"
      "https://niks3-public.ncaq.net/"
      "https://ncaq.cachix.org/"
      "https://nix-community.cachix.org/"
      "https://nix-on-droid.cachix.org/"
      "https://microvm.cachix.org/"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "niks3-public.ncaq.net-1:e/B9GomqDchMBmx3IW/TMQDF8sjUCQzEofKhpehXl04="
      "ncaq.cachix.org-1:XF346GXI2n77SB5Yzqwhdfo7r0nFcZBaHsiiMOEljiE="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nix-on-droid.cachix.org-1:56snoMJTXmDRC1Ei24CmKoUqvHJ9XCp+nidK7qkMQrU="
      "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqys="
    ];
  };
}
