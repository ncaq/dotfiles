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
      url = "github:nix-community/nix-on-droid/release-24.05";
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
      inputs.nixpkgs.follows = "nixpkgs-unstable";
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
        nixpkgs.follows = "nixpkgs-unstable"; # オリジナルで最新のRustのためにunstableを使っている。
        flake-parts.follows = "flake-parts";
      };
    };

    # 上流のREADMEはfollowsなしを標準構成としていますが、
    # unstableへfollowさせても評価とビルドは通り、画像と動画の生成も動きます。
    # stableだとtransformersが古く、
    # flash_attnが無い環境で辞書参照がKeyErrorになる不具合を踏んで、
    # SeedVR2のカスタムノードが読み込めません。
    # comfyui-nixのパッケージと一緒に実行するプログラムは、
    # 同じnixpkgsから取る必要があります。
    # 詳細は`nixos/host/bullet/comfyui/container.nix`の`comfyPkgs`のコメントを参照。
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

      # ディレクトリ内の全`.nix`ファイルをimportするヘルパー関数。
      importDirModules = import ./lib/import-dir-modules.nix { inherit lib; };
      # systemdサービス共通のハードニング設定。
      hardening = import ./lib/systemd-hardening.nix;
      # nixpkgsの共通設定。
      nixpkgsConfig = import ./lib/nixpkgs-config.nix { inherit lib; };
      # 全環境で共通のoverlays。
      overlays = [
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
        let
          # `renovate-recovery`ワークフローのClaude Codeへ渡すプラグインやプロンプトなどの設定一式。
          renovate-recovery-claude-config = pkgs.callPackage ./pkgs/renovate-recovery/claude-config.nix {
            konokaPlugins = inputs.konoka.packages.${system};
            git-hooks = inputs.git-hooks.packages.${system}.default;
            inherit renovate-recovery;
          };
          # `renovate-recovery`ワークフローが直接実行するTypeScriptの型検査とテスト。
          renovate-recovery = pkgs.callPackage ./pkgs/renovate-recovery { };
          # Gitリポジトリを購読するためのツール。
          # ビルドの中でsandwichのテストが走る。
          git-repo-subscribe = pkgs.callPackage ./pkgs/git-repo-subscribe {
            inherit (inputs) himari-src;
          };
          # 評価時にしか走らない純粋なNixのテストをderivationへ包む。
          #
          # `bullet/comfyui/workflow/lib/*-test.nix`は`validate.nix`が`assert`で走らせるが、
          # `lib/`のこれらは検査を使う側がホストの構成の中にあるため、
          # そのホストを評価しない限り走らない。
          # CIで必ず走らせたいので`checks`へ載せる。
          #
          # テストは全ての表明を通ると`true`を返す。
          # `builtins.seq`でその値を強制してからビルドを成功させる。
          mkNixTest =
            name: test:
            pkgs.runCommand name {
              passed = builtins.seq (
                assert test;
                test
              ) name;
            } ''echo "$passed" > "$out"'';
          systemd-specifier-test = mkNixTest "systemd-specifier-test" (
            import ./lib/systemd-specifier-test.nix { inherit lib; }
          );
          machine-address6-test = mkNixTest "machine-address6-test" (
            import ./lib/machine-address6-test.nix { inherit lib; }
          );
          comfyui-api-workflow-test = mkNixTest "comfyui-api-workflow-test" (
            import ./lib/comfyui-api-workflow-test.nix { inherit lib; }
          );
          safetensors-fp16 = pkgs.callPackage ./pkgs/safetensors-fp16 { };
          # Comfy-Orgの公式CLI。
          comfy-cli = pkgs.callPackage ./pkgs/comfy-cli { };
          # PLaMo Translateでローカル翻訳するCLI。
          # CIでCUDAをビルドしないようCPU版のllama.cppを渡す。
          # モデルとドラフトはラッパーの検査の分岐を通すためだけの値で、
          # 検査は推論しないので実在しなくてよい。
          plamo-translate-cli = pkgs.callPackage ./pkgs/plamo-translate-cli {
            inherit ((importPkgsUnstable system)) llama-cpp;
            model = "pfnet/plamo-3-translate-8b-GGUF:Q4_K_M";
            draftModel = "pfnet/plamo-3-translate-0.8b-GGUF:Q4_0";
          };
          # ワークフローを名前で呼ぶコマンド。
          # ビルドの中でsandwichのテストが走る。
          comfy-workflow = pkgs.callPackage ./pkgs/comfy-workflow {
            inherit comfy-cli;
            inherit (inputs) himari-src;
          };
          # アイドル中のComfyUIにメモリを解放させる常駐プロセス。
          # ビルドの中でsandwichのテストが走る。
          comfyui-idle-free-memory = pkgs.callPackage ./pkgs/comfyui-idle-free-memory {
            inherit (inputs) himari-src;
          };
          # GGUFのチャットテンプレートを取り出して書き戻すコマンド。
          # ビルドの中でsandwichのテストが走る。
          patch-gguf-chat-template = pkgs.callPackage ./pkgs/patch-gguf-chat-template {
            inherit (inputs) himari-src;
          };
          # GGUFの本体へ別ファイルのMTPのNextN層を足すコマンド。
          # ビルドの中でpytestのテストが走る。
          # モデルの量子化から呼ぶのと同じunstableのgguf-pyで組む。
          merge-gguf-nextn = (importPkgsUnstable system).callPackage ./pkgs/merge-gguf-nextn { };
          # PRコメントにnvd diffを投稿するコマンド。
          # ビルドの中でsandwichのテストが走る。
          nvd-pr-diff = pkgs.callPackage ./pkgs/nvd-pr-diff {
            inherit (inputs) himari-src;
          };
          # certspotterが検知したイベントをMackerelのチェックへ繋ぐコマンド。
          # ビルドの中でsandwichのテストが走る。
          certspotter-mackerel = pkgs.callPackage ./pkgs/certspotter-mackerel {
            inherit (inputs) himari-src;
          };
          # Open WebUIの利用者ごとの設定とプロフィールを宣言へ揃えるコマンド。
          # ビルドの中でsandwichのテストが走る。
          open-webui-user-settings-sync = pkgs.callPackage ./pkgs/open-webui-user-settings-sync {
            inherit (inputs) himari-src;
          };
          # 暗号化されたリムーバブルデバイスをマウントしてアンマウントするコマンド。
          # ビルドの中でsandwichのテストが走る。
          removable-crypt = pkgs.callPackage ./pkgs/removable-crypt {
            inherit (inputs) himari-src;
          };
          # GarageのS3バケットとキーを用意するコマンド。
          # ビルドの中でsandwichのテストが走る。
          garage-setup = pkgs.callPackage ./pkgs/garage-setup {
            inherit (inputs) himari-src;
          };
          # GitHub Actionsのランナーの登録トークンを発行してファイルに置くコマンド。
          # ビルドの中でsandwichのテストが走る。
          github-runner-registration-token = pkgs.callPackage ./pkgs/github-runner-registration-token {
            inherit (inputs) himari-src;
          };
          # flakeに定義された全ホストの閉包をGC rootとして登録するコマンド。
          # ビルドの中でsandwichのテストが走る。
          nix-gc-root-hosts = pkgs.callPackage ./pkgs/nix-gc-root-hosts {
            inherit (inputs) himari-src;
          };
          # seminarへのレイテンシを見てTailscaleのexit nodeを切り替えるdispatcherスクリプト。
          # ビルドの中でsandwichのテストが走る。
          tailscale-exit-node = pkgs.callPackage ./pkgs/tailscale-exit-node {
            inherit (inputs) himari-src;
          };
          # 有線接続中はWiFiの接続を切るNetworkManagerのdispatcherスクリプト。
          # ビルドの中でsandwichのテストが走る。
          wifi-wired-exclusive = pkgs.callPackage ./pkgs/wifi-wired-exclusive {
            inherit (inputs) himari-src;
          };
          # リポジトリ内のPythonをpyrightで型検査するためのderivation群。
          # ComfyUIのパッケージはoverlay経由でしか生えないが、
          # perSystemの`pkgs`にはoverlayが載っていないため、
          # overlayを載せる`importPkgsStable`から取る。
          # overlayが返すのはcomfyui-nix自身が固定したnixpkgsで組んだ成果物で、
          # 適用先の`pkgs`には依存しないため、どのpkgsから取っても結果は同じ。
          #
          # 取るのはCUDA版の`comfy-ui-cuda`にする。
          # bulletの`services.comfyui.gpuSupport = "cuda"`がこれを選ぶので、
          # 型検査が要求するtorchなどの依存の閉包が、
          # 実際に動かしている環境のものと共有される。
          # overlayの`comfyui`はCPUビルドで、
          # そちらを取ると誰も実行しない環境の閉包を新たに取得することになる。
          # 型検査用の環境は検査専用の依存を足すので、
          # bulletが使う環境そのものにはならない。
          pythonPyright = import ./lib/python-pyright.nix {
            inherit pkgs;
            comfyui = (importPkgsStable system).comfy-ui-cuda;
          };
          # ComfyUIの自作カスタムノードのうち、
          # ComfyUI本体に触れない部分のpytest。
          # PythonのバージョンをComfyUIに揃えるため、
          # 型検査と同じcomfyuiからインタプリタを取る。
          comfyui-custom-node-test = import ./lib/comfyui-custom-node-test.nix {
            inherit pkgs;
            comfyui = (importPkgsStable system).comfy-ui-cuda;
          };
          # CUDA版torchを含むcomfyuiはaarch64では現実的にビルドできないため、
          # 型検査とテストもx86_64-linuxでだけ提供します。
          hasComfyui = system == "x86_64-linux";
        in
        {
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

          checks =
            let
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
              nixosEvalChecks =
                lib.mapAttrs'
                  (
                    name: nixosConfig:
                    lib.nameValuePair "nixos-eval-${name}" (
                      pkgs.runCommand "nixos-eval-${name}" {
                        evaluated = builtins.seq nixosConfig.config.system.build.toplevel.drvPath name;
                      } ''echo "$evaluated" > "$out"''
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
                  "hm-eval" = pkgs.runCommand "hm-eval-${system}" {
                    evaluated = builtins.seq hmConfig.activationPackage.drvPath system;
                  } ''echo "$evaluated" > "$out"'';
                };
            in
            nixosEvalChecks
            // hmEvalChecks
            // {
              # `nix-fast-build`が見るのは`.#checks`だけで、
              # `packages`へ置いただけではCIでビルドされません。
              # ビルドが通ることと、
              # derivationの中で走るテストが通ることをCIで保証したいパッケージは、
              # `packages`と両方に並べます。
              inherit
                comfy-cli
                comfyui-api-workflow-test
                machine-address6-test
                merge-gguf-nextn
                plamo-translate-cli
                safetensors-fp16
                systemd-specifier-test
                ;
              # 警告を残さないために、CIでだけ`-Werror`で組む。
              certspotter-mackerel = certspotter-mackerel.override { werror = true; };
              open-webui-user-settings-sync = open-webui-user-settings-sync.override { werror = true; };
              removable-crypt = removable-crypt.override { werror = true; };
              garage-setup = garage-setup.override { werror = true; };
              github-runner-registration-token = github-runner-registration-token.override {
                werror = true;
              };
              nix-gc-root-hosts = nix-gc-root-hosts.override { werror = true; };
              tailscale-exit-node = tailscale-exit-node.override { werror = true; };
              wifi-wired-exclusive = wifi-wired-exclusive.override { werror = true; };
              comfy-workflow = comfy-workflow.override { werror = true; };
              comfyui-idle-free-memory = comfyui-idle-free-memory.override { werror = true; };
              git-repo-subscribe = git-repo-subscribe.override { werror = true; };
              patch-gguf-chat-template = patch-gguf-chat-template.override { werror = true; };
              nvd-pr-diff = nvd-pr-diff.override { werror = true; };
              inherit renovate-recovery;
              # 同じワークフローのClaude Codeへ渡す設定一式。
              # 使われるのはRenovateのPRが失敗した時だけなので、
              # konokaやgit-hooksの更新で壊れたことに普段のCIで気付けるようにします。
              inherit renovate-recovery-claude-config;
            }
            // lib.optionalAttrs hasComfyui {
              # リポジトリ内のPythonの型検査。
              pyright = pythonPyright.check;
              inherit comfyui-custom-node-test;
            };

          packages = {
            # flake.lockの管理バージョンをre-exportすることで安定した利用を促進。
            inherit (pkgs)
              disko
              fastfetch
              git
              home-manager
              ;
            # メモリに合わせて評価のワーカー数を抑える`nix-fast-build`のラッパー。
            # `./check.sh`がPATHに無い環境で`nix run`する対象です。
            nix-fast-build = pkgs.callPackage ./pkgs/nix-fast-build-wrapper.nix { };
            # `renovate-recovery`ワークフローが`claude-code-action`へ渡す実行ファイル。
            # NixOSのセルフホステッドランナーでは、
            # アクションが自分でダウンロードするバイナリは動的リンクを解決できず動かないため、
            # Nixでビルドしたものを指定します。
            inherit (pkgs) bun;
            inherit (importPkgsUnstable system) claude-code;
            # 同じワークフローが、Claude Codeの実行の記録を暗号化するのに使います。
            inherit (pkgs) gnupg;
            # 同じワークフローのClaude Codeへ渡すプラグインやプロンプトなどの設定一式。
            inherit renovate-recovery-claude-config;
            # Gitリポジトリを購読するためのツール。
            inherit git-repo-subscribe;
            # PRコメントにnvd diffを投稿するコマンド。
            inherit nvd-pr-diff;
            # safetensorsのF32テンソルをF16へ変換するコマンド。
            inherit safetensors-fp16;
            # Comfy-Orgの公式CLIと、それを包んでワークフローを名前で呼ぶコマンド。
            inherit comfy-cli comfy-workflow;
            # PLaMo Translateでローカル翻訳するCLI。
            inherit plamo-translate-cli;
            # アイドル中のComfyUIにメモリを解放させる常駐プロセス。
            inherit comfyui-idle-free-memory;
            # certspotterが検知したイベントをMackerelのチェックへ繋ぐコマンド。
            inherit certspotter-mackerel;
            # Open WebUIの利用者ごとの設定とプロフィールを宣言へ揃えるコマンド。
            inherit open-webui-user-settings-sync;
            # 暗号化されたリムーバブルデバイスをマウントしてアンマウントするコマンド。
            inherit removable-crypt;
            # GarageのS3バケットとキーを用意するコマンド。
            inherit garage-setup;
            # GitHub Actionsのランナーの登録トークンを発行してファイルに置くコマンド。
            inherit github-runner-registration-token;
            # flakeに定義された全ホストの閉包をGC rootとして登録するコマンド。
            inherit nix-gc-root-hosts;
            # seminarへのレイテンシを見てTailscaleのexit nodeを切り替えるdispatcherスクリプト。
            inherit tailscale-exit-node;
            # 有線接続中はWiFiの接続を切るNetworkManagerのdispatcherスクリプト。
            inherit wifi-wired-exclusive;
            # GGUFのチャットテンプレートを取り出して書き戻すコマンド。
            inherit patch-gguf-chat-template;
            # GGUFの本体へ別ファイルのMTPのNextN層を足すコマンド。
            inherit merge-gguf-nextn;
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
