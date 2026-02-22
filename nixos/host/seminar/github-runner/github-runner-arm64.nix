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
  inherit (githubRunnerShare)
    githubActionsRunnerPackages
    selfHostRunnerPackages
    dotfiles-github-runner
    users
    ;
  addr = config.machineAddresses.github-runner-arm64;
  # VMランナーやvirtiofsdなどはホスト(x86_64)で実行されるため、
  # ホストのpkgsを保持しておきます。
  # ゲストのpkgsはlocalSystem=aarch64-linuxのみでcrossSystem未指定のため、
  # buildPackagesも同じaarch64になってしまい、
  # microvm.nixのデフォルト設定ではqemu自体などのホストツールまでaarch64としてビルドされてしまいます。
  # それを避けるためにホストのpkgsを直接渡す必要がある部分があります。
  hostPkgs = pkgs;
  # クロスコンパイル(pkgsCross)ではなくネイティブaarch64パッケージセットを使います。
  # binfmt emulationによりクロスコンパイルではなくエミュレーションによるネイティブaarch64ビルドを使用します。
  # キャッシュヒット率が高くクロスコンパイル非対応パッケージもビルドできます。
  # microvm.nixのデフォルト設定とは`hostPkgs`のコメントの通り相性が悪いのですが、
  # クロスコンパイル非対応パッケージがgithub-runner自体が依存しているdotnetのため、
  # クロスコンパイルを使うことはできません。
  arm64Pkgs = import inputs.nixpkgs {
    localSystem = "aarch64-linux";
  };
  # ホストからも参照しやすいように束縛しておきます。
  stateDir = "${config.microvm.stateDir}/github-runner-arm64";
  # virtiofsでマウントできるのはファイルではなくディレクトリなので、
  # secretsDir以下にtokenファイルを置いてvirtiofsでマウントします。
  secretsDir = "${stateDir}/secrets";
in
{
  # aarch64-linuxバイナリをQEMU user-modeで透過的に実行できるようにします。
  # これはインストールするまでは有効にならないので、
  # 初回インストール時は`install.sh`スクリプト内部でハックして有効にする必要があります。
  microvm.vms.github-runner-arm64 = {
    pkgs = arm64Pkgs; # ARMのpkgsを渡すことでarmをエミュレーションすると伝えます。
    config =
      { pkgs, ... }:
      {
        system.stateVersion = "25.11";
        microvm = {
          vmHostPackages = hostPkgs; # クロスコンパイルを避けつつホストの環境を正しく反映させるためにホストのpkgsを渡します。
          hypervisor = "qemu";
          cpu = "max"; # QEMUのTCGモードで現在サポートしている最大機能セットのaarch64 CPUをエミュレートします。
          vcpu = 11; # 12(ホストのCPUスレッド) - 1
          mem = 16384; # 16GB
          interfaces = [
            {
              type = "tap";
              id = "vm-gh-arm64";
              mac = "02:00:00:00:00:51"; # 末尾バイトはゲストIPアドレスに対応
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
            (githubActionsRunnerPackages { inherit pkgs; }).minimal ++ selfHostRunnerPackages { inherit pkgs; };
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
          { Address = "${addr.host}/32"; }
        ];
        routes = [
          { Destination = "${addr.guest}/32"; }
        ];
      };
    };
    services."microvm@github-runner-arm64" =
      let
        secretMountName = utils.escapeSystemdPath (secretsDir + "/github-runner.mount");
      in
      {
        # エフェメラルランナーのためVM起動前にボリュームを削除して毎回クリーンな状態にします。
        # microvm.nixのcreateVolumesScriptがautoCreate=trueのボリュームを再作成します。
        preStart = lib.mkBefore ''
          rm -f ${stateDir}/nix-store-overlay.img
        '';
        # VM起動前にsecretsのbindマウントが完了していることを保証します。
        requires = [ secretMountName ];
        after = [ secretMountName ];
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
