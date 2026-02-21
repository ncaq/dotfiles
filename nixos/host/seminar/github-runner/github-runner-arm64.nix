/**
  QEMUエミュレーションによるaarch64 GitHub Actionsランナーです。
  x86_64ホスト上でaarch64ゲストをTCGモードで実行します。
*/
{
  pkgs,
  lib,
  utils,
  config,
  inputs,
  githubRunnerShare,
  ...
}:
let
  inherit (githubRunnerShare) users dotfiles-github-runner;
  # VMランナーやvirtiofsdなどはホスト(x86_64)で実行されるため、
  # ホストのpkgsを保持しておきます。
  # ゲストのpkgsはlocalSystem=aarch64-linuxのみでcrossSystem未指定のため、
  # buildPackagesも同じaarch64になってしまい、
  # microvm.nixのデフォルトではqemu自体などのホストツールまでaarch64としてビルドされてしまいます。
  hostPkgs = pkgs;
  addr = config.machineAddresses.github-runner-arm64;
  # クロスコンパイル(pkgsCross)ではなくネイティブaarch64パッケージセットを使います。
  # binfmt emulationによりクロスコンパイルではなくエミュレーションによるネイティブaarch64ビルドを使用します。
  # キャッシュヒット率が高くクロスコンパイル非対応パッケージもビルドできます。
  # microvm.nixのデフォルト設定とは相性が悪いのですが、
  # クロスコンパイル非対応パッケージがgithub-runnerのdotnet自体のため、
  # 避けることはできません。
  arm64Pkgs = import inputs.nixpkgs {
    localSystem = "aarch64-linux";
  };
  stateDir = "${config.microvm.stateDir}/github-runner-arm64";
  secretsDir = "${stateDir}/secrets";
in
{
  microvm.vms.github-runner-arm64 = {
    pkgs = arm64Pkgs;
    config =
      { pkgs, ... }:
      {
        system.stateVersion = "25.11";
        microvm = {
          # クロスコンパイルを避けつつホストの環境を正しく反映させるためにホストのpkgsを渡します。
          vmHostPackages = hostPkgs;
          hypervisor = "qemu";
          cpu = "max"; # QEMUのTCGモードで現在サポートしている最大機能セットのaarch64 CPUをエミュレートします。
          vcpu = 11; # 12(ホストのCPUスレッド) - 1
          mem = 16384; # 16GB
          interfaces = [
            {
              type = "tap";
              id = "vm-gh-arm64";
              mac = "02:00:00:00:00:50"; # 末尾バイトはゲストIPアドレスに対応
            }
          ];
          shares = [
            {
              tag = "ro-store";
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
              proto = "virtiofs";
            }
            {
              tag = "secrets";
              source = secretsDir;
              mountPoint = "/run/secrets";
              proto = "virtiofs";
            }
          ];
          # VM内でnix buildを実行可能にするための書き込み層です。
          writableStoreOverlay = "/nix/.rw-store";
          # 継続した永続化はしませんが、
          # RAMだけではビルド中に容量不足になる可能性があるため、
          # ディスクイメージをバックエンドにします。
          # VM起動時に毎回クリーンな状態になります。
          volumes = [
            {
              image = "nix-store-overlay.img";
              mountPoint = "/nix/.rw-store";
              size = 20480; # 20GB
              label = "nix-rw";
            }
          ];
        };
        # VM内のNixデーモンにホストと同じ設定を適用します。
        # コンテナと異なりソケット共有ができないため独立稼働しますが、
        # 一貫性が大事です。
        inherit users;
        nix.settings = config.nix.settings;
        networking = {
          hostName = "github-runner-arm64";
          firewall.trustedInterfaces = [ "eth0" ];
        };
        systemd = {
          network = {
            enable = true;
            networks."20-lan" = {
              matchConfig.Type = "ether";
              networkConfig = {
                Address = "${addr.guest}/24";
                Gateway = addr.host;
                DNS = [
                  "1.1.1.1"
                  "1.0.0.1"
                  "8.8.8.8"
                  "8.8.4.4"
                ];
              };
            };
          };
        };
        services.github-runners.dotfiles-arm64 = {
          enable = true;
          ephemeral = true;
          replace = true;
          user = "github-runner";
          group = "github-runner";
          extraLabels = [ "NixOS" ];
          # aarch64のpkgsセットを使ってパッケージをインストールします。
          extraPackages =
            (import ../../../../lib/github-actions-runner-packages.nix {
              inherit pkgs;
            }).minimal
            ++ (with pkgs; [
              attic-client
              cachix
            ]);
          tokenFile = "/run/secrets/github-runner";
          url = "https://github.com/ncaq/dotfiles";
          extraEnvironment = {
            ACTIONS_RUNNER_HOOK_JOB_STARTED = "${dotfiles-github-runner}/job-started-hook.js";
          };
        };
      };
  };
  systemd = {
    network = {
      enable = true;
      networks."20-vm-gh-arm64" = {
        matchConfig.Name = "vm-gh-arm64";
        addresses = [
          { Address = "${addr.host}/24"; }
        ];
      };
    };
    services."microvm@github-runner-arm64" = {
      # エフェメラルランナーのためVM起動前にボリュームを削除して毎回クリーンな状態にします。
      # microvm.nixのcreateVolumesScriptがautoCreate=trueのボリュームを再作成します。
      preStart = lib.mkBefore ''
        rm -f ${stateDir}/nix-store-overlay.img
      '';
      # VM起動前にsecretsのbindマウントが完了していることを保証します。
      requires = [ "${utils.escapeSystemdPath (secretsDir + "/github-runner.mount")}" ];
      after = [ "${utils.escapeSystemdPath (secretsDir + "/github-runner.mount")}" ];
    };
    tmpfiles.rules = [
      "d ${secretsDir} 0750 github-runner github-runner -"
    ];
  };
  # ホストのシークレットファイルをVMと共有しているディレクトリ内部にbindマウントします
  fileSystems."${secretsDir}/github-runner" = {
    device = config.sops.secrets."github-runner".path;
    options = [
      "bind"
      "ro"
    ];
  };
  # aarch64-linuxバイナリをQEMU user-modeで透過的に実行できるようにします。
  # これはインストールするまでは有効にならないので、
  # 初回インストール時は`install.sh`スクリプト内部でハックして有効にする必要があります。
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
}
