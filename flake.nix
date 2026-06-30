{
  description = "dotfiles, NixOS and home-manager.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-utils.url = "github:numtide/flake-utils";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-on-droid = {
      # 本来は公式の`github:nix-community/nix-on-droid`の最新版リリースを使いたい。
      # しかしNix-on-Droidが同梱するproot-termuxは`glibc 2.42`の`TCGETS2` ioctlに未対応で、
      # `26.05`の`glibc 2.42`ではインストールが`Permission denied`の権限エラーになる。
      # proot-termuxを修正する[PR](https://github.com/nix-community/nix-on-droid/pull/529)が、
      # まだ未マージなので暫定でそのブランチ(masterベース)を直接参照する。
      # 問題がなくなったら正式リリースに戻す。
      url = "github:newAM/nix-on-droid/update-proot";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };

    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

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
    let
      inherit (nixpkgs) lib;

      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      # ディレクトリ内の全`.nix`ファイルをimportするヘルパー関数。
      importDirModules = import ./lib/import-dir-modules.nix { inherit lib; };
      # nixpkgsの共通設定。
      nixpkgsConfig = import ./lib/nixpkgs-config.nix { inherit lib; };
      # 全環境で共通のoverlays。
      overlays = [
        inputs.firge-nix.overlays.default
        (import ./lib/snapper-btrfs-bin-overlay.nix)
      ];
      # system固有のpkgsを生成する関数。
      importPkgsFor =
        pkgset: system:
        import pkgset {
          inherit system overlays;
          config = nixpkgsConfig;
        };
      # systemごとにpkgsをメモ化するヘルパー。
      # 複数ホストやcheck/test-nixos-bootから同じ`system`で繰り返し呼ばれても、
      # 同じpkgs実体を返すようにして、評価時のメモリ消費を削減する。
      memoizePkgsPerSystem =
        f:
        let
          memo = lib.genAttrs systems f;
        in
        system: memo.${system};
      # systemを受け取り安定版のpkgsを生成する。
      importPkgsStable = memoizePkgsPerSystem (importPkgsFor nixpkgs);
      # systemを受け取り不安定版のpkgsを生成する。
      importPkgsUnstable = memoizePkgsPerSystem (importPkgsFor nixpkgs-unstable);

      mkNixosSystem = import ./lib/mk-nixos-system.nix {
        inherit
          lib
          importPkgsStable
          importPkgsUnstable
          importDirModules
          inputs
          ;
      };

      hostDefs = {
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

      nixosConfigurations = lib.mapAttrs (_: def: def.nixosSystem) hostDefs;

      testNixosBoot = import ./lib/test-nixos-boot.nix {
        inherit lib importPkgsStable hostDefs;
      };

      mkLinuxHomeManager = import ./lib/mk-linux-home-manager.nix {
        inherit
          importPkgsStable
          importPkgsUnstable
          importDirModules
          inputs
          ;
      };

      homeConfigurations = {
        "x86_64-linux" = mkLinuxHomeManager {
          system = "x86_64-linux";
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
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        home-manager.flakeModules.home-manager
        treefmt-nix.flakeModule
      ];

      inherit systems;

      flake = {
        inherit
          nixosConfigurations
          testNixosBoot
          homeConfigurations
          nixOnDroidConfigurations
          ;
      };

      perSystem =
        {
          pkgs,
          system,
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
              statix.enable = true;
              typos.enable = true;
              zizmor.enable = true;
            };
            settings.formatter = {
              editorconfig-checker = {
                command = pkgs.editorconfig-checker;
                includes = [ "*" ];
              };
              zizmor.options = [ "--pedantic" ];
            };
          };

          checks =
            let
              # NixOS構成の評価チェック(評価のみ、ビルドしない)
              nixosEvalChecks =
                lib.mapAttrs'
                  (
                    name: nixosConfig:
                    lib.nameValuePair "nixos-eval-${name}" (
                      builtins.seq nixosConfig.config.system.build.toplevel.drvPath (
                        pkgs.writeText "nixos-eval-${name}" name
                      )
                    )
                  )
                  (
                    lib.filterAttrs (
                      _: nixosConfig: nixosConfig.pkgs.stdenv.hostPlatform.system == system
                    ) nixosConfigurations
                  );
              # home-manager構成の評価チェック
              hmEvalChecks =
                let
                  hmConfig = homeConfigurations.${system} or null;
                in
                lib.optionalAttrs (hmConfig != null) {
                  "hm-eval" = builtins.seq hmConfig.activationPackage.drvPath (
                    pkgs.writeText "hm-eval-${system}" system
                  );
                };
            in
            nixosEvalChecks // hmEvalChecks;

          packages = {
            # flake.lockの管理バージョンをre-exportすることで安定した利用を促進。
            inherit (pkgs)
              disko
              fastfetch
              git
              home-manager
              nix-fast-build
              ;
            # PRコメントにnvd diffを投稿するスクリプト。
            nvd-pr-diff = pkgs.callPackage ./pkgs/nvd-pr-diff { };
          };

          devShells.default = pkgs.mkShell {
            buildInputs = with pkgs; [
              # treefmtで指定したプログラムの単体版。
              actionlint
              deadnix
              editorconfig-checker
              nixfmt
              prettier
              shellcheck
              shfmt
              statix
              typos
              zizmor

              # nixの関連ツール。
              nil

              # GitHub関連ツール。
              gh
            ];
          };
        };
    };

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
