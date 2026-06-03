{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  # GitHub Actionsのホステッドランナーをある程度互換しているパッケージリスト。
  githubActionsRunnerPackages = import ../../../../lib/github-actions-runner-packages.nix;
  # GitHubの標準ランナーにはないけれど個人的に含まれていて欲しいパッケージリスト。
  selfHostRunnerPackages =
    { pkgs, ... }:
    with pkgs;
    [
      cachix
      inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}.niks3
    ];
  # GitHub Actionsランナーの並列数。
  # 上位レベルでリソースを制限しているため、
  # 複数立ち上げてもサーバの全体のリソース量が破綻する心配はあまりありません。
  # あまりCPUを使い切れなくても、
  # Nixが動く時は大抵はキャッシュダウンロードのIO待ちなので、
  # 並列動作したほうが効率的です。
  runnerNum = 5;
  # runnerが使うTypeScriptコードをビルドしてGitHub Actionsで利用できるようにします。
  # 吐き出されるコードはピュアなJavaScriptなのでアーキテクチャ非依存です。
  dotfiles-github-runner = pkgs.buildNpmPackage {
    pname = "dotfiles-github-runner";
    version = "0.0.0";
    src = ./.;
    npmDeps = pkgs.importNpmLock { npmRoot = ./.; };
    inherit (pkgs.importNpmLock) npmConfigHook;
    dontNpmInstall = true;
    installPhase = ''
      runHook preInstall
      cp -r dist $out
      runHook postInstall
    '';
  };
  # ジョブ開始フックを実行する`.sh`ラッパー。
  # `ACTIONS_RUNNER_HOOK_JOB_STARTED`に`.js`を直接指定すると、
  # github-runner 2.334.0では`.js`フックのセットアップが、
  # .NET由来のパスエラー("Second path fragment must not be a drive or UNC name")で失敗します。
  # GitHubが公式にサポートするフック形式は`.sh`と`.ps1`のみなので、
  # nixpkgsのnodeでjsを実行する`.sh`ラッパー経由で呼び出します。
  # これによりランナー内蔵nodeのパス解決にも依存しなくなります。
  jobStartedHook = lib.getExe (
    pkgs.writeShellApplication {
      name = "job-started-hook.sh";
      runtimeInputs = with pkgs; [ nodejs ];
      text = ''exec node ${dotfiles-github-runner}/job-started-hook.js "$@"'';
    }
  );
  # GitHub Actionsランナーはホストのnixデーモンと通信するため、
  # 統一されたユーザ値を使います。
  user = config.serviceUser.github-runner;
  # ユーザーとグループ定義。
  # コンテナのnixコマンドはホストのnixデーモンと通信するため、
  # UIDとGIDはホストと一致させる必要があります。
  # なので明示的に定義します。
  # ホスト側でユーザーを解決できなければ`trusted-users`が機能しません。
  users = {
    users.github-runner = {
      isSystemUser = true;
      group = "github-runner";
      inherit (user) uid;
    };
    groups.github-runner.gid = user.gid;
  };
  # CI用のnix設定。
  # ホストの`nix.settings`をベースにしますが、
  # キャッシュ設定などはCIの設定側で設定するべきなのと、
  # ホスト側のビルドフックは動かないので、
  # 必要な設定だけを抜き出します。
  ciNixSettings = {
    inherit (config.nix.settings)
      experimental-features
      cores
      max-jobs
      accept-flake-config
      trusted-users
      ;
  };
in
{
  # 共有定義を他のランナーモジュールから利用可能にします。
  _module.args.githubRunnerShare = {
    inherit
      githubActionsRunnerPackages
      selfHostRunnerPackages
      runnerNum
      jobStartedHook
      users
      ciNixSettings
      ;
  };

  # ホストのnixデーモンがコンテナ内のgithub-runnerユーザーを信頼するよう設定します。
  inherit users;
  nix.settings.trusted-users = [ "github-runner" ];

  # Nix-on-Droidなどaarch64-linuxのビルドを必要にするものがあるので、
  # aarch64-linuxバイナリをQEMU user-modeで透過的に実行できるようにします。
  # ホストのnixデーモンがビルドサンドボックスを作成するため、
  # コンテナ側ではなくホストレベルで設定が必要です。
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  sops = {
    secrets = {
      # セルフホストランナーがGitHub Actionsに自身を登録するためのトークン。
      "runner-registration-token" = {
        sopsFile = ../../../../secrets/seminar/github-runner.yaml;
        key = "runner-registration-token";
        owner = "github-runner";
        group = "github-runner";
        mode = "0400";
      };
    };
  };
}
