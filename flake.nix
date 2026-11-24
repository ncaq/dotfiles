{
  description = "dotfiles, NixOS and home-manager.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      # flake-partsは`lib`だけを切り出した`nixpkgs.lib`リポジトリを別に持つが、
      # こちらのnixpkgsの`lib`で足りるので取得を重複させない。
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

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
      inputs = {
        nixpkgs.follows = "nixpkgs";
        # 上流の`default.nix`がflakeを使わない呼び出しに応えるための互換シム。
        # flakeとして使うこちらには不要なので、rootを指させて取得させない。
        flake-compat.follows = "";
      };
    };

    nix-on-droid = {
      # 最後のリリースブランチの`release-24.05`が同梱するprootは、
      # glibc 2.42以降の`tcgetattr`が発行するioctlを処理できず、nixpkgs 26.05では適用に失敗する。
      # 新しいprootを指しているのはmasterだけなので、リリースブランチではなくmasterを使う。
      # [Activation failed with nixos-unstable and 26.05](https://github.com/nix-community/nix-on-droid/issues/495)
      url = "github:nix-community/nix-on-droid";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
        # 以下は上流のbootstrap zipの生成とドキュメントの生成とフォーマッタのためだけの入力で、
        # こちらが使う`lib.nixOnDroidConfiguration`と`overlays.default`は触らない。
        # nixpkgsの形をしたものはこちらのnixpkgsへ向けて、
        # 取得するnixpkgsの一式が増えないようにする。
        # 他は使い道がないのでrootを指させて取得させない。
        nixpkgs-for-bootstrap.follows = "nixpkgs";
        nixpkgs-docs.follows = "nixpkgs";
        nix-formatter-pack.follows = "";
        nmd.follows = "";
      };
    };

    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        # GPUを通すcloud-hypervisorを組むためだけに上流がgit cloneしているSpectrum OSのソース。
        # こちらのVMは使わないので、rootを指させて取得させない。
        spectrum.follows = "";
      };
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

    xremap-flake = {
      url = "github:xremap/nix-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };

    # stableのtransformers 5.5.4では、
    # flash_attnが無い環境でSeedVR2のカスタムノードがKeyErrorで読み込めないので、
    # 直っている5.16.1以上を持つunstableへfollowさせます。
    # followする先を変える時は、
    # `nixos/host/bullet/comfyui/container.nix`が同じnixpkgsから取っているプログラムも揃えます。
    utensils-comfyui-nix = {
      url = "github:utensils/comfyui-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs-unstable";
        flake-parts.follows = "flake-parts";
      };
    };

    # stableのnixpkgsに入っている版はbrokenなので、上流のソースから組む。
    himari-src = {
      url = "github:ncaq/himari";
      flake = false;
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

    konoka = {
      url = "github:ncaq/konoka";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
      };
    };

    blue-prompt = {
      url = "github:ncaq/blue-prompt";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
      };
    };

    claude-desktop = {
      url = "github:nmcbride/claude-desktop-nix";
      inputs.nixpkgs.follows = "nixpkgs";
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

      # ディレクトリ内の全`.nix`ファイルをimportするヘルパ関数。
      importDirModules = import ./lib/import-dir-modules.nix { inherit lib; };
      # systemdサービス共通のハードニング設定。
      hardening = import ./lib/systemd-hardening.nix;
      # nixpkgsの共通設定。
      nixpkgsConfig = import ./lib/nixpkgs-config.nix { inherit lib; };
      # `pkgs/`の自作パッケージをトップレベルに生やすoverlay。
      localPackagesOverlay = import ./lib/local-packages-overlay.nix { inherit lib inputs; };
      # 全環境で共通のoverlays。
      overlays = [
        localPackagesOverlay
        (import ./lib/snapper-btrfs-bin-overlay.nix)
        inputs.utensils-comfyui-nix.overlays.default
        inputs.firge-nix.overlays.default
      ];
      # system固有のpkgsを生成する関数。
      importPkgsFor =
        pkgset: system:
        import pkgset {
          inherit system overlays;
          config = nixpkgsConfig;
        };
      # systemごとにpkgsをメモ化するヘルパ。
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
          hardening
          inputs
          ;
      };

      # 各ホストの静的な情報。
      # NixOSのoptionはホストの構成内で閉じていて他のホストからは参照できないため、
      # 他のホストが知る必要のある情報はここに書いて、
      # `specialArgs`の`hostInfo`として全ホストのモジュールに渡す。
      hostInfo = {
        "SSD0086" = {
          system = "x86_64-linux";
          # WSL2の上で動くホストかどうか。
          # 構成の`wsl.enable`を見ると、ホストの一覧を絞るだけで全ホストの構成を評価することになるので、
          # ここに静的に書く。
          # 構成と食い違っていないかは`nixos/core/host-info.nix`が確かめる。
          wsl = true;
        };
        "bullet" = {
          system = "x86_64-linux";
          # オンボード有線NICのMACアドレス。
          # seminarがWake-on-LANのmagic packetを送る宛先に使う。
          macAddress = "34:5a:60:bf:07:ad";
        };
        "creep" = {
          system = "x86_64-linux";
        };
        "seminar" = {
          system = "x86_64-linux";
        };
      };

      hostDefs = lib.mapAttrs (
        hostName: info:
        mkNixosSystem {
          inherit (info) system;
          inherit hostName hostInfo;
        }
      ) hostInfo;

      nixosConfigurations = lib.mapAttrs (_: def: def.nixosSystem) hostDefs;

      testNixosBoot = import ./test/nixos-boot {
        inherit
          lib
          importPkgsStable
          importDirModules
          hostDefs
          ;
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

      # `perSystem`の`ciJobs`を、flakeの出力の`ciJobs.<system>`にします。
      transposition.ciJobs.adHoc = true;

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
          config,
          pkgs,
          system,
          ...
        }:
        let
          pkgsUnstable = importPkgsUnstable system;
          # overlayが生やす`pkgs/`の自作パッケージの名前。
          localPackageNames = pkgs.localPackagesInfo.names;
          # `pkgs/`の自作パッケージ。
          # overlayを`pkgs`に当てた結果から、overlayが生やした名前の分だけを取り出す。
          localPackages = lib.getAttrs localPackageNames pkgs // {
            # CIでCUDAをビルドしないようCPU版のllama.cppを渡す。
            # モデルとドラフトはラッパの検査の分岐を通すためだけの値で、
            # 検査は推論しないので実在しなくてよい。
            plamo-translate-cli = pkgs.plamo-translate-cli.override {
              inherit (pkgsUnstable) llama-cpp;
              model = "pfnet/plamo-3-translate-8b-GGUF:Q4_K_M";
              draftModel = "pfnet/plamo-3-translate-0.8b-GGUF:Q4_0";
            };
          };
          # 自作のパッケージが`passthru.tests`に置いたテスト。
          # パッケージ自身の`checkPhase`に入れると、
          # テストを書き換えただけでパッケージのstoreパスが変わってしまう時に使う。
          # `<パッケージの名前>-test-<テストの名前>`という名前で1つのderivationへ束ねる。
          #
          # テストごとに`checks`の属性にしないのは、
          # 属性の名前を決めるのに全てのパッケージの`tests`を見ることになるから。
          # `checks`の属性名を数えるだけで全てのパッケージが評価されて、
          # `callCabal2nix`のIFDまで走ってしまう。
          # `nix-eval-jobs`のワーカは起動するたびに属性名を数えるので、その度に同じ評価を繰り返す。
          # 束ねておけば、パッケージを評価するのはこの属性を評価する時だけになる。
          localPackageTests = pkgs.linkFarm "local-package-tests" (
            lib.concatMapAttrs (
              name: package: lib.mapAttrs' (test: lib.nameValuePair "${name}-test-${test}") (package.tests or { })
            ) localPackages
          );
          # 自作のパッケージの名前がnixpkgsの属性と重なっていないかのチェック。
          # 重なった時に何が起きるかは`lib/local-packages-overlay.nix`に書いてある。
          # 黙って差し替わらないように評価を止めて、移行するか名前を変えるかを決める。
          # overlayはunstableにも当てるので、unstableの属性とも比べる。
          # 強制をenv属性の中に置く理由は下の`nixosEvalChecks`と同じ。
          localPackagesNameCollision =
            let
              collisions = lib.unique (
                pkgs.localPackagesInfo.collisions ++ pkgsUnstable.localPackagesInfo.collisions
              );
            in
            pkgs.runCommand "local-packages-name-collision" {
              checked = builtins.seq (lib.assertMsg (
                collisions == [ ]
              ) "自作のパッケージの名前がnixpkgsの属性と重なっています: ${lib.concatStringsSep ", " collisions}") system;
            } ''echo "$checked" > "$out"'';
          # このシステムで動くホスト。
          # 属性名を数えるだけでホストの構成を評価しないように、
          # 構成の中の`pkgs`ではなく静的な`hostDefs`の`system`で絞る。
          hostDefsOfSystem = lib.filterAttrs (_: def: def.system == system) hostDefs;
          # NixOS構成の評価チェック(評価のみ、ビルドしない)。
          # env属性の中の`builtins.seq`がinstantiation時にのみ完全評価を強制する。
          # この形には2つの理由がある。
          # チェック対象の値自体を`builtins.seq`や`writeText`のtextで強制すると、
          # `nix flake show`のような属性値に触れるだけのコマンドでも、
          # 全ホストの完全評価が走り数GBのメモリを消費してしまう。
          # (`writeText`は関数適用の時点でtextを強制評価する。)
          # かといって`drvPath`の文字列をそのままenv属性に含めると、
          # 文字列コンテキスト経由でtoplevelへのビルド依存が発生してしまい、
          # チェックのビルドがシステム全体の実ビルドになってしまう。
          nixosEvalChecks = lib.mapAttrs' (
            name: def:
            lib.nameValuePair "nixos-eval-${name}" (
              pkgs.runCommand "nixos-eval-${name}" {
                evaluated = builtins.seq def.nixosSystem.config.system.build.toplevel.drvPath name;
              } ''echo "$evaluated" > "$out"''
            )
          ) hostDefsOfSystem;
          # home-manager構成の評価チェック
          hmEvalChecks = lib.optionalAttrs (homeConfigurations ? ${system}) {
            "hm-eval" = pkgs.runCommand "hm-eval-${system}" {
              evaluated = builtins.seq homeConfigurations.${system}.activationPackage.drvPath system;
            } ''echo "$evaluated" > "$out"'';
          };
          # 評価だけを確かめるチェック。
          # 手元の`./check.sh`を軽くするためのもので、
          # 実際にビルドする`ciJobs`では要らなくなる。
          evalChecks = nixosEvalChecks // hmEvalChecks;
          # 実装のファイルに書けない評価のテスト(`*.test.nix`)を、ファイルごとにderivationへ包んだもの。
          nixTests = import ./test/collect-nix-tests.nix {
            inherit lib;
            inherit (pkgs) runCommand;
          };
          # リポジトリ内のPythonをpyrightで型検査するためのderivation群。
          #
          # 取るのはCUDA版の`comfy-ui-cuda`にする。
          # bulletの`services.comfyui.gpuSupport = "cuda"`がこれを選ぶので、
          # 型検査が要求するtorchなどの依存のクロージャが、
          # 実際に動かしている環境のものと共有される。
          # overlayの`comfyui`はCPUビルドで、
          # そちらを取ると誰も実行しない環境のクロージャを新たに取得することになる。
          # 型検査用の環境は検査専用の依存を足すので、
          # bulletが使う環境そのものにはならない。
          pythonPyright = import ./lib/python-pyright.nix {
            inherit pkgs;
            comfyui = pkgs.comfy-ui-cuda;
          };
          # CUDA版torchを含むcomfyuiはaarch64では現実的にビルドできないため、
          # 型検査はx86_64-linuxでだけ提供します。
          hasComfyui = system == "x86_64-linux";
        in
        {
          # flake-partsが渡す既定の`pkgs`はoverlayを載せていないので、
          # ホストと同じ設定とoverlayのものに差し替える。
          _module.args.pkgs = importPkgsStable system;

          treefmt.config = {
            projectRootFile = "flake.nix";
            programs = {
              actionlint.enable = true;
              deadnix.enable = true;
              fourmolu.enable = true;
              hlint.enable = true;
              nixf-diagnose.enable = true;
              nixfmt.enable = true;
              prettier.enable = true;
              ruff-check.enable = true;
              ruff-format.enable = true;
              rustfmt.enable = true;
              shellcheck.enable = true;
              shfmt.enable = true;
              statix.enable = true;
              taplo.enable = true;
              typos.enable = true;
              zizmor.enable = true;
            };
            settings.formatter = {
              # cabal-gildのモジュール自動発見機能に対応するため、
              # Haskellソースファイルの変更も検知してcabal-gildを実行します。
              # treefmt-nixの上流では、
              # 変更されたファイルだけを修正したいと言われてマージされていませんが、
              # ローカルで使う分には問題ありません。
              # [cabal-gild discover module](https://github.com/numtide/treefmt-nix/pull/384)
              cabal-gild = {
                command = lib.getExe (
                  pkgs.writeShellApplication {
                    name = "cabal-gild-wrapper";
                    runtimeInputs = with pkgs; [
                      git
                      haskellPackages.cabal-gild
                      parallel
                    ];
                    text = ''
                      git ls-files -z "*.cabal" | parallel --null "cabal-gild --io {}"
                    '';
                  }
                );
                includes = [
                  "*.cabal"
                  # Haskellソースファイルの変更を検知するために含める
                  "*.hs"
                  "*.lhs"
                  "*.hsc"
                  "*.chs"
                  "*.hsig"
                  "*.lhsig"
                ];
              };
              editorconfig-checker = {
                command = pkgs.editorconfig-checker;
                includes = [ "*" ];
              };
              zizmor.options = [ "--pedantic" ];
            };
          };

          # CIのセルフホステッドランナが1回の`nix-fast-build`でまとめて処理するもの。
          # `CHECK_OUTPUT=ciJobs ./check.sh`で実行する。
          #
          # `checks`との違いは、ホストとhome-managerの構成を評価するだけでなく実際にビルドして、
          # ホストのブートテストも走らせること。
          # 手元の`./check.sh`でこれらを毎回ビルドするのは重いので`checks`とは分けている。
          #
          # 1回にまとめる理由は、ホストの構成の評価が重いこと。
          # 評価のチェック、ビルド、ブートテストを別々のジョブに分けると、
          # 同じホストをジョブごとに評価し直すことになる。
          # まとめれば評価は1回で済み、`nix-eval-jobs`のワーカへ並列に割り振られる。
          #
          # `nix-eval-jobs`は属性を名前の順に評価して、評価が済んだものからビルドが始まる。
          # 全体の時間を決めるのは評価、ビルド、VMのブートが直列に並ぶブートテストなので、
          # 先頭で評価されるように`boot-test-`という名前にしている。
          ciJobs =
            removeAttrs config.checks (builtins.attrNames evalChecks)
            // lib.mapAttrs' (
              name: def: lib.nameValuePair "nixos-${name}" def.nixosSystem.config.system.build.toplevel
            ) hostDefsOfSystem
            // lib.optionalAttrs (homeConfigurations ? ${system}) {
              home-manager = homeConfigurations.${system}.activationPackage;
            }
            // lib.mapAttrs' (name: lib.nameValuePair "boot-test-${name}") (
              lib.filterAttrs (name: _: hostDefsOfSystem ? ${name}) testNixosBoot
            );

          checks =
            evalChecks
            // nixTests
            # `nix-fast-build`が見るのは`.#checks`だけで、
            # `packages`へ置いただけではCIでビルドされないので、
            # 自作のパッケージは全てビルドとderivationの中のテストを確かめる。
            // localPackages
            // {
              local-package-tests = localPackageTests;
              local-packages-name-collision = localPackagesNameCollision;
            }
            // lib.optionalAttrs hasComfyui {
              # リポジトリ内のPythonの型検査。
              pyright = pythonPyright.check;
            };

          packages =
            localPackages
            // {
              # flake.lockの管理バージョンをre-exportすることで安定した利用を促進。
              inherit (pkgs)
                disko
                fastfetch
                git
                home-manager
                ;
              # 既定の引数を足した`nix-fast-build`のラッパ。
              # `./check.sh`がPATHに無い環境で`nix run`する対象です。
              nix-fast-build = pkgs.nix-fast-build-wrapper;
            }
            // lib.optionalAttrs hasComfyui {
              # pyrightがPython環境とComfyUIのソースを辿るためのディレクトリ。
              # `.envrc`が`.typecheck`という名前のout-linkを張ります。
              typecheck = pythonPyright.typecheckDir;
            };

          devShells.default = pkgs.mkShell {
            buildInputs = with pkgs; [
              # treefmtで指定したプログラムの単体版。
              actionlint
              deadnix
              editorconfig-checker
              nixf-diagnose
              nixfmt
              prettier
              ruff
              shellcheck
              shfmt
              statix
              typos
              zizmor

              # リポジトリ内のPythonの型検査。
              # `.envrc`が用意する`.typecheck`と`pyrightconfig.json`を読みます。
              pyright

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
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "niks3-public.ncaq.net-1:e/B9GomqDchMBmx3IW/TMQDF8sjUCQzEofKhpehXl04="
      "ncaq.cachix.org-1:XF346GXI2n77SB5Yzqwhdfo7r0nFcZBaHsiiMOEljiE="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
}
